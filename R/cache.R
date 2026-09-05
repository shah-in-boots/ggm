# cache.R --------------------------------------------------------------
# StudyCache: a handle on a WFDB record group and the files gram keeps
# beside it
#
# A study is a group of sibling files sharing one stem:
#   <stem>.dat            canonical signal bytes, never touched
#   <stem>.hea            WFDB header, never touched
#   <stem>.<annotator>    optional WFDB annotation files, never touched
#   <stem>.gram.json      manifest: what gram knows about this record
#   <stem>.gram.parquet   the overview table (or <stem>.gram.rds)
#
# Everything gram writes is named `<stem>.gram.*`, so one rule keeps its own
# files out of annotator discovery and the package name marks where a file
# came from. The manifest is shared between parts of gram: each writer reads
# it, replaces only its own section, and writes the whole file back through
# a temporary file. The `cache` section is written by build_overview() in
# R/overview.R; bookmarks and the annotation sidecar will own sections of
# their own. A rebuild can therefore never clobber something a person
# authored.
#
# This file holds the handle itself: what a record group is, where its files
# are, what the manifest says about them, and how to read raw signal out of
# it. The overview pyramid the manifest describes is built and read back in
# R/overview.R.

gm_cache_version <- 1L


# class -----------------------------------------------------------------

#' Handle to a WFDB study
#'
#' Create with [study_cache()].
#'
#' @param stem WFDB record name without extension.
#' @param dir Directory containing the canonical `.dat` and `.hea` files.
#' @param data_path Path to the `.dat` signal file.
#' @param header_path Path to the `.hea` header file.
#' @param annotation_paths Named paths to optional WFDB annotation files.
#' @param manifest_path Path to the `<stem>.gram.json` manifest, which may not
#'   exist yet.
#' @param fingerprint Cheap identity of the record files at open time, used to
#'   tell a cache built from this record from one built from an earlier
#'   version of it.
#' @param channels Channel labels from the WFDB header.
#' @param units Channel units from the WFDB header.
#' @param sample_rate Sampling frequency in Hz.
#' @param n_samples Sample count per channel.
#' @param header Parsed `EGM::read_header()` object.
#'
#' @noRd
StudyCache <- S7::new_class(
  "StudyCache",
  properties = list(
    stem             = S7::class_character,
    dir              = S7::class_character,
    data_path        = S7::class_character,
    header_path      = S7::class_character,
    annotation_paths = S7::class_character,
    manifest_path    = S7::class_character,
    fingerprint      = S7::class_character,
    channels         = S7::class_character,
    units            = S7::class_character,
    sample_rate      = S7::class_double,
    n_samples        = S7::class_double,
    header           = S7::class_any
  ),
  validator = function(self) {
    if (length(self@stem) != 1L || !nzchar(self@stem)) {
      "@stem must be a single non-empty name"
    } else if (length(self@dir) != 1L || !nzchar(self@dir)) {
      "@dir must be a single non-empty path"
    } else {
      NULL
    }
  }
)

S7::method(print, StudyCache) <- function(x, ...) {
  cat("<StudyCache> ", x@stem, "\n", sep = "")
  cat("  record dir: ", x@dir, "\n", sep = "")
  cat("  channels:   ", length(x@channels), "\n", sep = "")
  cat("  rate:       ", format(x@sample_rate), " Hz\n", sep = "")
  cat("  samples:    ", format(x@n_samples, scientific = FALSE), "\n", sep = "")
  cat("  signal:     ", basename(x@data_path),
      if (file.exists(x@data_path)) "" else "  [missing]", "\n", sep = "")
  cat("  header:     ", basename(x@header_path),
      if (file.exists(x@header_path)) "" else "  [missing]", "\n", sep = "")

  annotators <- cache_annotators(x)
  cat("  annotators: ", if (length(annotators)) {
    paste(annotators, collapse = ", ")
  } else {
    "[none found]"
  }, "\n", sep = "")

  section <- gm_manifest(x)
  cat("  overview:   ", if (!is.null(section)) {
    paste0(
      length(section$buckets), " level", if (length(section$buckets) != 1L) "s",
      " (", min(section$buckets), "..", max(section$buckets), " samples), ",
      section$file
    )
  } else if (gm_manifest_has_cache(x)) {
    "stale, run build_overview(cache, rebuild = TRUE)"
  } else {
    "[not built]"
  }, "\n", sep = "")
  invisible(x)
}


# constructor -----------------------------------------------------------

#' Open a WFDB record as a StudyCache handle
#'
#' Validates the record group, reads the header with [EGM::read_header()],
#' discovers annotation sidecars, and remembers where gram's own files for
#' this record live. Nothing is read from the signal and nothing is written.
#'
#' @param path Any file in the record group, or a bare stem.
#' @param cache_dir Directory holding `<stem>.gram.json` and the overview
#'   table. Defaults to the record directory. Point it elsewhere when the
#'   study folder is read-only; the same `cache_dir` must then be given every
#'   time the study is opened, since that is where the handle looks.
#' @param annotators Optional WFDB annotator extensions to require, such as
#'   `"qrs"` or `"ann"`. `NULL` discovers existing sidecars.
#' @param data_ext Signal extension, without the dot.
#' @param header_ext Header extension, without the dot.
#' @return A `StudyCache`.
#' @seealso [build_overview()], [read_viewport()], [read_study_signal()]
#' @export
study_cache <- function(
  path,
  cache_dir = NULL,
  annotators = NULL,
  data_ext = "dat",
  header_ext = "hea"
) {
  record <- gm_parse_record_path(path)
  dir <- normalizePath(record$dir, winslash = "/", mustWork = FALSE)
  stem <- record$stem

  dataPath <- file.path(dir, paste0(stem, ".", data_ext))
  headerPath <- file.path(dir, paste0(stem, ".", header_ext))

  missingCore <- c(dataPath, headerPath)[!file.exists(c(dataPath, headerPath))]
  if (length(missingCore) > 0L) {
    stop(
      "not a complete WFDB record group, missing: ",
      paste(basename(missingCore), collapse = ", "),
      call. = FALSE
    )
  }

  cacheDir <- if (is.null(cache_dir)) {
    dir
  } else {
    normalizePath(cache_dir, winslash = "/", mustWork = FALSE)
  }

  hdr <- gm_read_record_header(stem, dir)

  # Size and mtime of the signal, size and md5 of the header. The signal is
  # too large to hash on every open; the header is tiny and names everything
  # about the record that matters. sprintf() rather than paste() so a 516 MB
  # size does not print as 5.16e+08.
  rawInfo <- file.info(dataPath)
  headerInfo <- file.info(headerPath)
  fingerprint <- paste(
    basename(dataPath),
    sprintf("%.0f", rawInfo$size),
    format(rawInfo$mtime, "%Y-%m-%dT%H:%M:%OS3%z", tz = "UTC"),
    basename(headerPath),
    sprintf("%.0f", headerInfo$size),
    unname(tools::md5sum(headerPath)),
    sep = "|"
  )

  StudyCache(
    stem = stem,
    dir = dir,
    data_path = dataPath,
    header_path = headerPath,
    annotation_paths = gm_find_annotation_paths(
      dir = dir,
      stem = stem,
      annotators = annotators,
      data_ext = data_ext,
      header_ext = header_ext
    ),
    manifest_path = file.path(cacheDir, paste0(stem, ".gram.json")),
    fingerprint = fingerprint,
    channels = hdr$channels,
    units = hdr$units,
    sample_rate = hdr$sample_rate,
    n_samples = hdr$n_samples,
    header = hdr$header
  )
}

gm_read_record_header <- function(stem, dir) {
  header <- EGM::read_header(record = stem, record_dir = dir)
  recordLine <- attr(header, "record_line")

  channels <- as.character(header$label)
  channels[is.na(channels) | channels == ""] <- paste0(
    "CH", seq_along(channels)[is.na(channels) | channels == ""]
  )

  units <- as.character(header$ADC_units)
  if (length(units) == 0L) {
    units <- rep(NA_character_, length(channels))
  }

  list(
    header = header,
    channels = channels,
    units = units,
    sample_rate = as.double(recordLine$frequency),
    n_samples = as.double(recordLine$samples)
  )
}


# path helpers ----------------------------------------------------------

gm_parse_record_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    stop("`path` must be a single non-empty path", call. = FALSE)
  }

  stem <- basename(path)
  stem <- sub("\\.gram\\.[^.]+$", "", stem)
  stem <- sub("\\.[^.]+$", "", stem)
  list(dir = dirname(path), stem = stem)
}

gm_find_annotation_paths <- function(dir, stem, annotators = NULL,
                                  data_ext = "dat", header_ext = "hea") {
  if (!is.null(annotators)) {
    annotators <- as.character(annotators)
    annotators <- annotators[nzchar(annotators)]
    paths <- file.path(dir, paste0(stem, ".", annotators))
    missing <- paths[!file.exists(paths)]
    if (length(missing) > 0L) {
      stop(
        "requested annotation file(s) not found: ",
        paste(basename(missing), collapse = ", "),
        call. = FALSE
      )
    }
    names(paths) <- annotators
    return(paths)
  }

  files <- list.files(
    dir,
    pattern = paste0("^", gm_regex_escape(stem), "\\."),
    full.names = TRUE,
    no.. = TRUE
  )
  if (length(files) == 0L) {
    return(stats::setNames(character(), character()))
  }

  ext <- sub(paste0("^", gm_regex_escape(stem), "\\."), "", basename(files))
  excluded <- c(data_ext, header_ext, "txt")
  # anything gram wrote beside the record is `<stem>.gram.*`, never an annotator
  keep <- !(tolower(ext) %in% tolower(excluded)) &
    !startsWith(tolower(ext), "gram.") &
    !dir.exists(files)
  paths <- files[keep]
  names(paths) <- ext[keep]
  paths
}

gm_regex_escape <- function(x) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
}


# public accessors ------------------------------------------------------

#' All paths in a study group
#'
#' @param cache A `StudyCache`.
#' @return Named character vector of record paths: `data`, `header`,
#'   `manifest`, one `annotation_<ext>` per sidecar, and `cache` when an
#'   overview has been built.
#' @export
cache_paths <- function(cache) {
  paths <- c(
    data = cache@data_path,
    header = cache@header_path,
    manifest = cache@manifest_path
  )

  if (length(cache@annotation_paths) > 0L) {
    ann <- cache@annotation_paths
    names(ann) <- paste0("annotation_", names(ann))
    paths <- c(paths, ann)
  }

  section <- gm_manifest(cache)
  if (!is.null(section)) {
    paths <- c(paths, cache = file.path(dirname(cache@manifest_path), section$file))
  }

  paths
}

#' Available WFDB annotator sidecars
#'
#' @param cache A `StudyCache`.
#' @return Character vector of annotator extensions.
#' @export
cache_annotators <- function(cache) {
  names(cache@annotation_paths) %||% character()
}


# manifest --------------------------------------------------------------

#' Read the cache section of a study manifest
#'
#' `<stem>.gram.json` is shared between the parts of gram that write beside a
#' record; each owns one section. This reads the `cache` section and decides
#' whether the overview it describes may be used for the open record.
#'
#' @param cache A `StudyCache`.
#' @return The `cache` section as a list, or `NULL` when the manifest or the
#'   section is absent, the section was written by another format version,
#'   its fingerprint is not the open record's (the record changed since the
#'   build), or the table it names is missing. `NULL` is the answer to "may I
#'   use this overview", and every caller treats it as "not built" rather than
#'   serving a stale reduction as if it were current.
#' @keywords internal
gm_manifest <- function(cache) {
  if (!file.exists(cache@manifest_path)) {
    return(NULL)
  }
  section <- jsonlite::read_json(cache@manifest_path, simplifyVector = TRUE)$cache
  if (is.null(section)) {
    return(NULL)
  }
  if (!identical(as.integer(section$version), gm_cache_version)) {
    return(NULL)
  }
  if (!identical(as.character(section$fingerprint), cache@fingerprint)) {
    return(NULL)
  }
  if (!file.exists(file.path(dirname(cache@manifest_path), section$file))) {
    return(NULL)
  }
  section
}

# A cache section exists at all, usable or not; the print method uses this to
# tell "stale" from "never built".
gm_manifest_has_cache <- function(cache) {
  file.exists(cache@manifest_path) &&
    !is.null(jsonlite::read_json(cache@manifest_path)$cache)
}


# signal reads ----------------------------------------------------------

#' Read raw WFDB signal for a visible window
#'
#' Thin wrapper around [EGM::read_signal()] that uses the parsed header stored
#' in the `StudyCache`.
#'
#' @param cache A `StudyCache`.
#' @param begin,end Times delimiting a half-open range. These follow
#'   [EGM::validate_time_parameters()]: time-only character values are elapsed
#'   from the record start, dated character values and `POSIXt` objects are
#'   absolute, and `difftime` values are elapsed durations. Numeric values are
#'   not accepted.
#' @param interval A duration after `begin` that takes precedence over `end`.
#'   Numeric values are seconds; compact durations such as `"100 ms"` are also
#'   accepted.
#' @param channels Channel labels or indices. Defaults to all channels.
#' @param units Units passed to [EGM::read_signal()].
#' @return An `EGM` signal table.
#' @export
read_study_signal <- function(cache,
                              begin = NULL,
                              end = NULL,
                              interval = NULL,
                              channels = NULL,
                              units = c("physical", "digital")) {
  units <- match.arg(units)

  EGM::read_signal(
    record = cache@stem,
    record_dir = cache@dir,
    header = cache@header,
    begin = begin,
    end = end,
    interval = interval,
    units = units,
    channels = gm_cache_channel_index(cache, channels)
  )
}

# Channel positions, from labels or positions. Positions are what EGM and the
# overview table are addressed by, so two channels with the same label still
# read as two channels.
gm_cache_channel_index <- function(cache, channels = NULL) {
  if (is.null(channels) || length(channels) == 0L) {
    return(seq_along(cache@channels))
  }

  if (is.numeric(channels)) {
    if (any(is.na(channels)) || any(channels < 1L | channels > length(cache@channels))) {
      stop("requested channel indices are outside the available range", call. = FALSE)
    }
    return(as.integer(channels))
  }

  channels <- as.character(channels)
  matched <- match(channels, cache@channels)
  missing <- is.na(matched)
  if (any(missing)) {
    matched[missing] <- match(toupper(channels[missing]), toupper(cache@channels))
  }
  if (any(is.na(matched))) {
    stop(
      "unknown channel(s): ",
      paste(sQuote(channels[is.na(matched)]), collapse = ", "),
      call. = FALSE
    )
  }

  matched
}

gm_study_seconds_to_sample <- function(seconds, sample_rate) {
  rawSample <- seconds * sample_rate
  tolerance <- .Machine$double.eps * max(1, abs(rawSample)) * 8
  ceiling(rawSample - tolerance)
}
