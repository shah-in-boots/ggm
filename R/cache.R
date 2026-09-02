# class -----------------------------------------------------------------

#' Handle to a WFDB study
#'
#' Create with [study_cache()].
#'
#' @param stem WFDB record name without extension.
#' @param dir Directory containing the canonical `.dat` and `.hea` files.
#' @param raw_path Path to the `.dat` signal file.
#' @param header_path Path to the `.hea` header file.
#' @param annotation_paths Named paths to optional WFDB annotation files.
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
    raw_path         = S7::class_character,
    header_path      = S7::class_character,
    annotation_paths = S7::class_character,
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
  cat("  signal:     ", basename(x@raw_path),
      if (file.exists(x@raw_path)) "" else "  [missing]", "\n", sep = "")
  cat("  header:     ", basename(x@header_path),
      if (file.exists(x@header_path)) "" else "  [missing]", "\n", sep = "")

  annotators <- cache_annotators(x)
  cat("  annotators: ", if (length(annotators)) {
    paste(annotators, collapse = ", ")
  } else {
    "[none found]"
  }, "\n", sep = "")
  invisible(x)
}


# constructor -----------------------------------------------------------

#' Open a WFDB record as a StudyCache handle
#'
#' @param path Any file in the record group, or a bare stem.
#' @param annotators Optional WFDB annotator extensions to require, such as
#'   `"qrs"` or `"ann"`. `NULL` discovers existing sidecars.
#' @param raw_ext Signal extension, without the dot.
#' @param header_ext Header extension, without the dot.
#' @return A `StudyCache`.
#' @export
study_cache <- function(
  path,
  annotators = NULL,
  raw_ext = "dat",
  header_ext = "hea"
) {
  record <- gm_parse_record_path(path)
  dir <- normalizePath(record$dir, winslash = "/", mustWork = FALSE)
  stem <- record$stem

  rawPath <- file.path(dir, paste0(stem, ".", raw_ext))
  headerPath <- file.path(dir, paste0(stem, ".", header_ext))

  missingCore <- c(rawPath, headerPath)[!file.exists(c(rawPath, headerPath))]
  if (length(missingCore) > 0L) {
    stop(
      "not a complete WFDB record group, missing: ",
      paste(basename(missingCore), collapse = ", "),
      call. = FALSE
    )
  }

  hdr <- gm_read_record_header(stem, dir)

  StudyCache(
    stem = stem,
    dir = dir,
    raw_path = rawPath,
    header_path = headerPath,
    annotation_paths = gm_find_annotation_paths(
      dir = dir,
      stem = stem,
      annotators = annotators,
      raw_ext = raw_ext,
      header_ext = header_ext
    ),
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

  list(dir = dirname(path), stem = sub("\\.[^.]+$", "", basename(path)))
}

gm_find_annotation_paths <- function(dir, stem, annotators = NULL,
                                  raw_ext = "dat", header_ext = "hea") {
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
  excluded <- c(raw_ext, header_ext, "txt")
  keep <- !(tolower(ext) %in% tolower(excluded)) & !dir.exists(files)
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
#' @return Named character vector of record paths.
#' @export
cache_paths <- function(cache) {
  paths <- c(raw = cache@raw_path, header = cache@header_path)

  if (length(cache@annotation_paths) > 0L) {
    ann <- cache@annotation_paths
    names(ann) <- paste0("annotation_", names(ann))
    paths <- c(paths, ann)
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


# viewport reads --------------------------------------------------------

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
    channels = gm_resolve_cache_channels(cache, channels)
  )
}

gm_resolve_cache_channels <- function(cache, channels = NULL) {
  if (is.null(channels) || length(channels) == 0L) {
    return(cache@channels)
  }

  if (is.numeric(channels)) {
    if (any(is.na(channels)) || any(channels < 1L | channels > length(cache@channels))) {
      stop("requested channel indices are outside the available range", call. = FALSE)
    }
    return(cache@channels[as.integer(channels)])
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

  cache@channels[matched]
}

gm_study_seconds_to_sample <- function(seconds, sample_rate) {
  rawSample <- seconds * sample_rate
  tolerance <- .Machine$double.eps * max(1, abs(rawSample)) * 8
  ceiling(rawSample - tolerance)
}
