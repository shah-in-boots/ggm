# cache.R --------------------------------------------------------------
# StudyCache: WFDB record-group handle + derived overview cache
#
# A study is a group of sibling WFDB files sharing one stem:
#   <stem>.dat              canonical signal bytes
#   <stem>.hea              WFDB header
#   <stem>.<annotator>      optional WFDB annotation files
#   <stem>.cache.parquet    derived signal overview built by gram
#   <stem>.cache.json       manifest for the derived cache
#
# The raw signal is never converted to Parquet. Raw viewport reads go through
# EGM::read_signal(), which can seek into the WFDB .dat file. The Parquet file
# built here stores only regenerable bucket summaries for overview/navigation.

cacheManifestVersion <- 4L
cacheAlgorithm <- "bucket-extrema-v1"


# class -----------------------------------------------------------------

#' Handle to a WFDB study and its derived overview cache
#'
#' Create with [study_cache()]. A `StudyCache` validates the WFDB record group,
#' keeps the header metadata needed for range reads, and optionally attaches an
#' existing `*.cache.parquet` overview.
#'
#' @param stem WFDB record name without extension.
#' @param dir Directory containing the canonical `.dat` and `.hea` files.
#' @param cache_dir Directory containing the derived cache files.
#' @param raw_path Path to the `.dat` signal file.
#' @param header_path Path to the `.hea` header file.
#' @param annotation_paths Named paths to optional WFDB annotation files.
#' @param cache_path Path to `<stem>.cache.parquet`.
#' @param manifest_path Path to `<stem>.cache.json`.
#' @param channels Channel labels from the WFDB header.
#' @param units Channel units from the WFDB header.
#' @param sample_rate Sampling frequency in Hz.
#' @param n_samples Sample count per channel.
#' @param fingerprint Fast record fingerprint used for cache invalidation.
#' @param header Parsed `EGM::read_header()` object.
#' @param level_factor Geometric factor between overview levels.
#' @param levels Data frame of available levels.
#' @param created_at ISO 8601 cache build timestamp.
#'
#' @noRd
StudyCache <- S7::new_class(
  "StudyCache",
  properties = list(
    stem             = S7::class_character,
    dir              = S7::class_character,
    cache_dir        = S7::class_character,
    raw_path         = S7::class_character,
    header_path      = S7::class_character,
    annotation_paths = S7::class_character,
    cache_path       = S7::class_character,
    manifest_path    = S7::class_character,
    channels         = S7::class_character,
    units            = S7::class_character,
    sample_rate      = S7::class_double,
    n_samples        = S7::class_double,
    fingerprint      = S7::class_character,
    header           = S7::class_any,
    level_factor     = S7::class_integer,
    levels           = S7::class_data.frame,
    created_at       = S7::class_character
  ),
  validator = function(self) {
    if (length(self@stem) != 1L || !nzchar(self@stem)) {
      "@stem must be a single non-empty name"
    } else if (length(self@dir) != 1L || !nzchar(self@dir)) {
      "@dir must be a single non-empty path"
    } else if (length(self@cache_dir) != 1L || !nzchar(self@cache_dir)) {
      "@cache_dir must be a single non-empty path"
    } else if (!is.na(self@level_factor) && self@level_factor < 2L) {
      "@level_factor must be >= 2"
    } else {
      NULL
    }
  }
)

S7::method(print, StudyCache) <- function(x, ...) {
  cat("<StudyCache> ", x@stem, "\n", sep = "")
  cat("  record dir: ", x@dir, "\n", sep = "")
  cat("  cache dir:  ", x@cache_dir, "\n", sep = "")
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

  if (cache_is_built(x)) {
    cat("  cache:      ", basename(x@cache_path), "\n", sep = "")
    cat("  built:      ", x@created_at, "\n", sep = "")
    cat("  levels:\n")
    print(
      x@levels[, c("level", "source", "bucket_samples", "rows"), drop = FALSE],
      row.names = FALSE
    )
  } else {
    cat("  cache:      [not built]\n")
  }
  invisible(x)
}


# constructor -----------------------------------------------------------

#' Open a WFDB record as a StudyCache handle
#'
#' Accepts a bare record path or any sibling file from the group, derives the
#' required `.dat` and `.hea` paths, reads the WFDB header with
#' [EGM::read_header()], discovers optional annotation sidecars, and attaches an
#' existing cache manifest when present.
#'
#' @param path Any file in the record group, or a bare stem.
#' @param cache_dir Directory for `*.cache.parquet` and `*.cache.json`. Defaults
#'   to the record directory when writable, otherwise a per-user cache directory.
#' @param annotators Optional WFDB annotator extensions to require, such as
#'   `"qrs"` or `"ann"`. `NULL` discovers existing sidecars.
#' @param raw_ext Signal extension, without the dot.
#' @param header_ext Header extension, without the dot.
#' @return A `StudyCache`.
#' @export
study_cache <- function(
  path,
  cache_dir = NULL,
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
  fingerprint <- gm_record_fingerprint(rawPath, headerPath)
  cacheDir <- gm_choose_cache_dir(dir, stem, fingerprint, cache_dir)

  annotationPaths <- gm_find_annotation_paths(
    dir = dir,
    stem = stem,
    annotators = annotators,
    raw_ext = raw_ext,
    header_ext = header_ext
  )

  cache <- StudyCache(
    stem = stem,
    dir = dir,
    cache_dir = cacheDir,
    raw_path = rawPath,
    header_path = headerPath,
    annotation_paths = annotationPaths,
    cache_path = file.path(cacheDir, paste0(stem, ".cache.parquet")),
    manifest_path = file.path(cacheDir, paste0(stem, ".cache.json")),
    channels = hdr$channels,
    units = hdr$units,
    sample_rate = hdr$sample_rate,
    n_samples = hdr$n_samples,
    fingerprint = fingerprint,
    header = hdr$header,
    level_factor = NA_integer_,
    levels = data.frame(),
    created_at = NA_character_
  )

  if (file.exists(cache@manifest_path)) {
    cache <- gm_attach_manifest(cache)
  }
  cache
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

  dir <- dirname(path)
  stem <- basename(path)
  stem <- sub("\\.cache\\.(parquet|json)$", "", stem, ignore.case = TRUE)
  stem <- sub("\\.[^.]+$", "", stem)

  list(dir = dir, stem = stem)
}

gm_choose_cache_dir <- function(record_dir, stem, fingerprint, cache_dir = NULL) {
  if (!is.null(cache_dir)) {
    cache_dir <- normalizePath(cache_dir, winslash = "/", mustWork = FALSE)
  } else if (dir.exists(record_dir) && file.access(record_dir, mode = 2L) == 0L) {
    cache_dir <- record_dir
  } else {
    id <- substr(gsub("[^A-Za-z0-9]", "", fingerprint), 1L, 24L)
    cache_dir <- file.path(tools::R_user_dir("gram", "cache"), paste0(stem, "-", id))
  }

  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  normalizePath(cache_dir, winslash = "/", mustWork = FALSE)
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
  excluded <- c(raw_ext, header_ext, "cache.parquet", "cache.json", "parquet", "txt")
  keep <- !(tolower(ext) %in% tolower(excluded)) & !dir.exists(files)
  paths <- files[keep]
  names(paths) <- ext[keep]
  paths
}

gm_regex_escape <- function(x) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
}

gm_record_fingerprint <- function(raw_path, header_path) {
  rawInfo <- file.info(raw_path)
  headerInfo <- file.info(header_path)

  paste(
    basename(raw_path),
    as.numeric(rawInfo$size),
    format(rawInfo$mtime, "%Y-%m-%dT%H:%M:%OS3%z", tz = "UTC"),
    basename(header_path),
    as.numeric(headerInfo$size),
    unname(tools::md5sum(header_path)),
    sep = "|"
  )
}


# public accessors ------------------------------------------------------

#' All paths in a study group
#'
#' @param cache A `StudyCache`.
#' @return Named character vector of canonical and cache paths.
#' @export
cache_paths <- function(cache) {
  paths <- c(
    raw = cache@raw_path,
    header = cache@header_path,
    cache = cache@cache_path,
    manifest = cache@manifest_path
  )

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

#' Has the overview cache been built for this study?
#'
#' @param cache A `StudyCache`.
#' @return `TRUE` when a manifest is attached and the cache file exists.
#' @export
cache_is_built <- function(cache) {
  nrow(cache@levels) > 0L && file.exists(cache@cache_path)
}


# manifest --------------------------------------------------------------

gm_attach_manifest <- function(cache) {
  manifest <- jsonlite::read_json(cache@manifest_path, simplifyVector = TRUE)

  if (!identical(as.integer(manifest$version), cacheManifestVersion)) {
    stop(
      "cache manifest version ", manifest$version,
      " is not supported; rebuild with overwrite = TRUE",
      call. = FALSE
    )
  }

  if (!identical(as.character(manifest$algorithm), cacheAlgorithm)) {
    stop(
      "cache algorithm ", sQuote(manifest$algorithm),
      " is not supported; rebuild with overwrite = TRUE",
      call. = FALSE
    )
  }

  if (!file.exists(cache@cache_path)) {
    warning(
      "cache manifest exists but cache parquet is missing: ",
      cache@cache_path,
      call. = FALSE
    )
    return(cache)
  }

  if (!identical(as.character(manifest$fingerprint), cache@fingerprint)) {
    warning(
      "WFDB record changed since cache was built; ",
      "consider build_study_cache(overwrite = TRUE)",
      call. = FALSE
    )
  }

  levels <- as.data.frame(manifest$levels)
  levels$path <- ifelse(levels$level == 0L, cache@raw_path, cache@cache_path)
  levels$filter_level <- ifelse(
    levels$level == 0L,
    NA_integer_,
    as.integer(levels$level)
  )

  cache@level_factor <- as.integer(manifest$level_factor)
  cache@levels <- levels
  cache@created_at <- as.character(manifest$created_at)
  cache
}


# cache building --------------------------------------------------------

#' Build the derived overview cache for a WFDB study
#'
#' Streams raw signal chunks from [EGM::read_signal()], reduces them to bucket
#' extrema, and writes all overview levels to `<stem>.cache.parquet`. The raw
#' `.dat` file remains the source for high-resolution reads.
#'
#' @param cache A `StudyCache` from [study_cache()].
#' @param bucket_samples Finest overview bucket size, in samples.
#' @param level_factor Geometric factor between overview levels.
#' @param target_top_rows Add coarser levels until the top level has at most this
#'   many buckets.
#' @param max_levels Safety cap on overview depth, excluding raw level 0.
#' @param chunk_seconds Raw read size during the streaming pass.
#' @param units Units to cache, passed to [EGM::read_signal()].
#' @param overwrite Rebuild even if a cache already exists.
#' @return The updated `StudyCache`.
#' @export
build_study_cache <- function(cache,
                              bucket_samples = 64L,
                              level_factor = 4L,
                              target_top_rows = 1e5,
                              max_levels = 6L,
                              chunk_seconds = 60,
                              units = c("physical", "digital"),
                              overwrite = FALSE) {
  units <- match.arg(units)

  if (!requireNamespace("nanoparquet", quietly = TRUE)) {
    stop(
      "Building the overview cache needs the 'nanoparquet' package.",
      call. = FALSE
    )
  }

  if (!overwrite && cache_is_built(cache)) {
    message("cache already built (overwrite = TRUE to rebuild)")
    return(cache)
  }
  if (!overwrite && file.exists(cache@manifest_path)) {
    message("cache already on disk, attaching it")
    return(gm_attach_manifest(cache))
  }

  bucket_samples <- as.integer(bucket_samples)
  level_factor <- as.integer(level_factor)
  max_levels <- as.integer(max_levels)

  if (is.na(bucket_samples) || bucket_samples < 2L) {
    stop("`bucket_samples` must be an integer >= 2", call. = FALSE)
  }
  if (is.na(level_factor) || level_factor < 2L) {
    stop("`level_factor` must be an integer >= 2", call. = FALSE)
  }
  if (is.na(max_levels) || max_levels < 1L) {
    stop("`max_levels` must be an integer >= 1", call. = FALSE)
  }
  if (!is.finite(chunk_seconds) || chunk_seconds <= 0) {
    stop("`chunk_seconds` must be a positive number", call. = FALSE)
  }

  sampleRate <- cache@sample_rate
  nSamples <- cache@n_samples
  if (!is.finite(sampleRate) || sampleRate <= 0) {
    stop("WFDB header does not contain a valid sampling frequency", call. = FALSE)
  }
  if (!is.finite(nSamples) || nSamples <= 0) {
    stop("WFDB header does not contain a valid sample count", call. = FALSE)
  }

  levelPlan <- gm_plan_cache_levels(
    n_samples = nSamples,
    sample_rate = sampleRate,
    bucket_samples = bucket_samples,
    level_factor = level_factor,
    target_top_rows = target_top_rows,
    max_levels = max_levels
  )

  chunkSamples <- max(bucket_samples, as.integer(round(chunk_seconds * sampleRate)))
  chunkSamples <- max(bucket_samples, floor(chunkSamples / bucket_samples) * bucket_samples)

  message("building level 1 from WFDB chunks ...")
  baseChunks <- list()
  starts <- seq(0, nSamples - 1, by = chunkSamples)
  for (i in seq_along(starts)) {
    startSample <- starts[[i]]
    endSample <- min(startSample + chunkSamples, nSamples)
    signal <- EGM::read_signal(
      record = cache@stem,
      record_dir = cache@dir,
      header = cache@header,
      begin = gm_study_elapsed_time(cache, startSample / sampleRate),
      end = gm_study_elapsed_time(cache, endSample / sampleRate),
      units = units,
      channels = cache@channels
    )

    baseChunks[[i]] <- gm_summarize_signal_chunk(
      signal = as.data.frame(signal),
      channels = cache@channels,
      level = 1L,
      bucket_samples = levelPlan$bucket_samples[levelPlan$level == 1L],
      sample_rate = sampleRate
    )
  }

  levelTables <- list()
  levelTables[["1"]] <- do.call(rbind, baseChunks)
  row.names(levelTables[["1"]]) <- NULL

  if (nrow(levelPlan) > 2L) {
    for (level in levelPlan$level[levelPlan$level > 1L]) {
      message("building level ", level, " from level ", level - 1L, " ...")
      levelTables[[as.character(level)]] <- gm_aggregate_cache_level(
        x = levelTables[[as.character(level - 1L)]],
        channels = cache@channels,
        level = level,
        bucket_samples = levelPlan$bucket_samples[levelPlan$level == level],
        sample_rate = sampleRate
      )
    }
  }

  overview <- do.call(rbind, levelTables)
  overview <- overview[order(overview$level, overview$start_sample), , drop = FALSE]
  row.names(overview) <- NULL

  levelRows <- vapply(levelTables, nrow, integer(1))
  levelPlan$rows[match(as.integer(names(levelRows)), levelPlan$level)] <- levelRows

  cacheTmp <- tempfile(
    pattern = paste0(cache@stem, ".cache-"),
    tmpdir = cache@cache_dir,
    fileext = ".parquet"
  )
  manifestTmp <- tempfile(
    pattern = paste0(cache@stem, ".cache-"),
    tmpdir = cache@cache_dir,
    fileext = ".json"
  )
  on.exit(unlink(c(cacheTmp, manifestTmp)), add = TRUE)

  nanoparquet::write_parquet(
    overview,
    cacheTmp,
    compression = "zstd",
    options = nanoparquet::parquet_options(num_rows_per_row_group = 100000L)
  )

  manifest <- list(
    version = cacheManifestVersion,
    algorithm = cacheAlgorithm,
    stem = cache@stem,
    fingerprint = cache@fingerprint,
    units = units,
    sample_rate = sampleRate,
    n_samples = nSamples,
    channels = as.list(cache@channels),
    channel_units = as.list(cache@units),
    bucket_samples = bucket_samples,
    level_factor = level_factor,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z", tz = "UTC"),
    levels = levelPlan
  )

  jsonlite::write_json(
    manifest,
    manifestTmp,
    auto_unbox = TRUE,
    digits = NA,
    pretty = TRUE
  )

  # Publish the parquet first and the manifest last. A manifest on disk is the
  # completion marker for a usable cache.
  unlink(cache@cache_path)
  if (!file.rename(cacheTmp, cache@cache_path)) {
    stop("failed to publish cache file: ", cache@cache_path, call. = FALSE)
  }

  unlink(cache@manifest_path)
  if (!file.rename(manifestTmp, cache@manifest_path)) {
    unlink(cache@cache_path)
    stop("failed to publish cache manifest: ", cache@manifest_path, call. = FALSE)
  }

  gm_attach_manifest(cache)
}

gm_plan_cache_levels <- function(n_samples, sample_rate, bucket_samples,
                              level_factor, target_top_rows, max_levels) {
  levels <- data.frame(
    level = 0L,
    source = "wfdb",
    bucket_samples = 1,
    bucket_seconds = 1 / sample_rate,
    rows = as.double(n_samples)
  )

  level <- 1L
  bucket <- as.double(bucket_samples)
  repeat {
    rows <- ceiling(n_samples / bucket)
    levels <- rbind(
      levels,
      data.frame(
        level = level,
        source = "cache",
        bucket_samples = bucket,
        bucket_seconds = bucket / sample_rate,
        rows = as.double(rows)
      )
    )

    if (rows <= target_top_rows || level >= max_levels) {
      break
    }

    level <- level + 1L
    bucket <- bucket * level_factor
  }

  levels
}

gm_summarize_signal_chunk <- function(signal, channels, level,
                                   bucket_samples, sample_rate) {
  samples <- as.double(signal$sample)
  bucketStart <- floor(samples / bucket_samples) * bucket_samples
  groups <- split(seq_along(samples), bucketStart)
  starts <- as.double(names(groups))
  n <- lengths(groups)

  out <- data.frame(
    level = as.integer(level),
    bucket_samples = as.double(bucket_samples),
    start_sample = starts,
    end_sample = starts + n,
    time = starts / sample_rate,
    n = as.double(n)
  )

  for (ch in channels) {
    values <- signal[[ch]]
    stats <- gm_summarize_channel_groups(values, samples, groups)
    out[[gm_cache_col(ch, "first")]] <- stats$first
    out[[gm_cache_col(ch, "first_sample")]] <- stats$first_sample
    out[[gm_cache_col(ch, "min")]] <- stats$min
    out[[gm_cache_col(ch, "min_sample")]] <- stats$min_sample
    out[[gm_cache_col(ch, "max")]] <- stats$max
    out[[gm_cache_col(ch, "max_sample")]] <- stats$max_sample
    out[[gm_cache_col(ch, "last")]] <- stats$last
    out[[gm_cache_col(ch, "last_sample")]] <- stats$last_sample
  }

  out
}

gm_summarize_channel_groups <- function(values, samples, groups) {
  n <- length(groups)
  first <- minVal <- maxVal <- last <- numeric(n)
  firstSample <- minSample <- maxSample <- lastSample <- numeric(n)

  for (i in seq_along(groups)) {
    idx <- groups[[i]]
    vals <- values[idx]
    sampleVals <- samples[idx]
    minIdx <- which.min(vals)
    maxIdx <- which.max(vals)

    first[[i]] <- vals[[1L]]
    firstSample[[i]] <- sampleVals[[1L]]
    minVal[[i]] <- vals[[minIdx]]
    minSample[[i]] <- sampleVals[[minIdx]]
    maxVal[[i]] <- vals[[maxIdx]]
    maxSample[[i]] <- sampleVals[[maxIdx]]
    last[[i]] <- vals[[length(vals)]]
    lastSample[[i]] <- sampleVals[[length(sampleVals)]]
  }

  list(
    first = first,
    first_sample = firstSample,
    min = minVal,
    min_sample = minSample,
    max = maxVal,
    max_sample = maxSample,
    last = last,
    last_sample = lastSample
  )
}

gm_aggregate_cache_level <- function(x, channels, level, bucket_samples, sample_rate) {
  bucketStart <- floor(x$start_sample / bucket_samples) * bucket_samples
  groups <- split(seq_len(nrow(x)), bucketStart)
  starts <- as.double(names(groups))

  out <- data.frame(
    level = as.integer(level),
    bucket_samples = as.double(bucket_samples),
    start_sample = starts,
    end_sample = vapply(groups, function(idx) max(x$end_sample[idx]), numeric(1)),
    time = starts / sample_rate,
    n = vapply(groups, function(idx) sum(x$n[idx]), numeric(1))
  )

  for (ch in channels) {
    firstCol <- gm_cache_col(ch, "first")
    firstSampleCol <- gm_cache_col(ch, "first_sample")
    minCol <- gm_cache_col(ch, "min")
    minSampleCol <- gm_cache_col(ch, "min_sample")
    maxCol <- gm_cache_col(ch, "max")
    maxSampleCol <- gm_cache_col(ch, "max_sample")
    lastCol <- gm_cache_col(ch, "last")
    lastSampleCol <- gm_cache_col(ch, "last_sample")

    out[[firstCol]] <- vapply(groups, function(idx) x[[firstCol]][idx[[1L]]], numeric(1))
    out[[firstSampleCol]] <- vapply(groups, function(idx) {
      x[[firstSampleCol]][idx[[1L]]]
    }, numeric(1))
    out[[lastCol]] <- vapply(groups, function(idx) x[[lastCol]][idx[[length(idx)]]], numeric(1))
    out[[lastSampleCol]] <- vapply(groups, function(idx) {
      x[[lastSampleCol]][idx[[length(idx)]]]
    }, numeric(1))

    out[[minCol]] <- vapply(groups, function(idx) min(x[[minCol]][idx]), numeric(1))
    out[[minSampleCol]] <- vapply(groups, function(idx) {
      pos <- which.min(x[[minCol]][idx])
      x[[minSampleCol]][idx[[pos]]]
    }, numeric(1))

    out[[maxCol]] <- vapply(groups, function(idx) max(x[[maxCol]][idx]), numeric(1))
    out[[maxSampleCol]] <- vapply(groups, function(idx) {
      pos <- which.max(x[[maxCol]][idx])
      x[[maxSampleCol]][idx[[pos]]]
    }, numeric(1))
  }

  out
}

gm_cache_col <- function(channel, statistic) {
  paste0(channel, "__", statistic)
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
  channels <- gm_resolve_cache_channels(cache, channels)

  EGM::read_signal(
    record = cache@stem,
    record_dir = cache@dir,
    header = cache@header,
    begin = begin,
    end = end,
    interval = interval,
    units = units,
    channels = channels
  )
}

gm_study_start_time <- function(cache) {
  startTime <- attr(cache@header, "record_line")$start_time
  if (!inherits(startTime, "POSIXt") || length(startTime) != 1L) {
    return(as.POSIXct(NA))
  }
  startTime
}

gm_study_elapsed_time <- function(cache, seconds) {
  startTime <- gm_study_start_time(cache)
  if (!is.na(startTime)) {
    return(startTime + seconds)
  }
  as.difftime(seconds, units = "secs")
}

gm_normalize_study_window <- function(cache,
                                   begin = NULL,
                                   end = NULL,
                                   interval = NULL) {
  EGM::validate_time_parameters(
    begin = begin,
    end = end,
    interval = interval,
    start_time = gm_study_start_time(cache),
    study_duration = cache@n_samples / cache@sample_rate
  )
}

gm_study_seconds_to_sample <- function(seconds, sample_rate) {
  rawSample <- seconds * sample_rate
  tolerance <- .Machine$double.eps * max(1, abs(rawSample)) * 8
  ceiling(rawSample - tolerance)
}

#' Pick the best source level for a viewport
#'
#' Returns raw level 0 when the visible window is already near screen
#' resolution. Otherwise it selects the finest overview level whose emitted
#' extrema stay near `points_per_pixel`.
#'
#' @param cache A built `StudyCache`.
#' @param window_seconds Visible time span.
#' @param pixel_width Plot width in device pixels.
#' @param points_per_pixel Target maximum rendered points per pixel.
#' @return One row of `cache@levels`.
#' @export
select_cache_level <- function(cache,
                               window_seconds,
                               pixel_width,
                               points_per_pixel = 4) {
  if (!cache_is_built(cache)) {
    stop("cache not built yet; run build_study_cache() first", call. = FALSE)
  }
  if (!is.finite(window_seconds) || window_seconds <= 0) {
    stop("`window_seconds` must be positive", call. = FALSE)
  }
  if (!is.finite(pixel_width) || pixel_width <= 0) {
    stop("`pixel_width` must be positive", call. = FALSE)
  }

  rawPointsPerPixel <- window_seconds * cache@sample_rate / pixel_width
  if (rawPointsPerPixel <= points_per_pixel) {
    return(cache@levels[cache@levels$level == 0L, , drop = FALSE])
  }

  secondsPerPixel <- window_seconds / pixel_width
  targetBucket <- 2 * secondsPerPixel / points_per_pixel
  overview <- cache@levels[cache@levels$level > 0L, , drop = FALSE]
  usable <- overview[overview$bucket_seconds >= targetBucket, , drop = FALSE]

  if (nrow(usable) > 0L) {
    return(usable[which.min(usable$bucket_seconds), , drop = FALSE])
  }

  overview[which.max(overview$bucket_seconds), , drop = FALSE]
}

#' Read an overview cache window
#'
#' @param cache A built `StudyCache`.
#' @inheritParams read_study_signal
#' @param channels Channel labels. Defaults to all channels.
#' @param level Overview level to read. Defaults to automatic level selection.
#' @param pixel_width Plot width used when `level = NULL`.
#' @param points_per_pixel Target maximum rendered points per pixel.
#' @return Data frame with `sample`, `time`, `channel`, `value`, and `statistic`.
#' @export
read_cache_overview <- function(cache,
                                begin = NULL,
                                end = NULL,
                                interval = NULL,
                                channels = NULL,
                                level = NULL,
                                pixel_width = 1000,
                                points_per_pixel = 4) {
  if (!cache_is_built(cache)) {
    stop("cache not built yet; run build_study_cache() first", call. = FALSE)
  }
  if (!requireNamespace("nanoparquet", quietly = TRUE)) {
    stop("Reading the overview cache needs the 'nanoparquet' package.", call. = FALSE)
  }
  window <- gm_normalize_study_window(cache, begin, end, interval)
  beginSeconds <- window$begin
  endSeconds <- window$end

  channels <- gm_resolve_cache_channels(cache, channels)

  if (endSeconds <= beginSeconds) {
    return(gm_cache_points_from_rows(data.frame(), channels, cache@sample_rate))
  }

  if (is.null(level)) {
    selected <- select_cache_level(
      cache = cache,
      window_seconds = endSeconds - beginSeconds,
      pixel_width = pixel_width,
      points_per_pixel = points_per_pixel
    )
    level <- selected$level[[1L]]
  }
  if (identical(as.integer(level), 0L)) {
    stop("selected level is raw; use read_study_signal()", call. = FALSE)
  }

  required <- c(
    "level", "start_sample", "end_sample",
    unlist(lapply(channels, function(ch) {
      gm_cache_col(ch, c(
        "first", "first_sample",
        "min", "min_sample",
        "max", "max_sample",
        "last", "last_sample"
      ))
    }), use.names = FALSE)
  )

  overview <- nanoparquet::read_parquet(cache@cache_path, col_select = required)
  overview <- as.data.frame(overview)

  beginSample <- gm_study_seconds_to_sample(beginSeconds, cache@sample_rate)
  endSample <- gm_study_seconds_to_sample(endSeconds, cache@sample_rate)
  overview <- overview[
    overview$level == level &
      overview$start_sample < endSample &
      overview$end_sample > beginSample,
    ,
    drop = FALSE
  ]

  gm_cache_points_from_rows(overview, channels, sample_rate = cache@sample_rate)
}

gm_cache_points_from_rows <- function(rows, channels, sample_rate) {
  if (nrow(rows) == 0L || length(channels) == 0L) {
    return(data.frame(
      sample = numeric(),
      time = numeric(),
      channel = character(),
      value = numeric(),
      statistic = character(),
      stringsAsFactors = FALSE
    ))
  }

  pieces <- vector("list", length(channels))

  for (i in seq_along(channels)) {
    ch <- channels[[i]]
    channelPieces <- vector("list", nrow(rows))

    for (j in seq_len(nrow(rows))) {
      samples <- c(
        rows[[gm_cache_col(ch, "first_sample")]][[j]],
        rows[[gm_cache_col(ch, "min_sample")]][[j]],
        rows[[gm_cache_col(ch, "max_sample")]][[j]],
        rows[[gm_cache_col(ch, "last_sample")]][[j]]
      )
      values <- c(
        rows[[gm_cache_col(ch, "first")]][[j]],
        rows[[gm_cache_col(ch, "min")]][[j]],
        rows[[gm_cache_col(ch, "max")]][[j]],
        rows[[gm_cache_col(ch, "last")]][[j]]
      )
      statistic <- c("first", "min", "max", "last")

      keep <- !duplicated(samples)
      point <- data.frame(
        sample = samples[keep],
        time = samples[keep] / sample_rate,
        channel = ch,
        value = values[keep],
        statistic = statistic[keep],
        stringsAsFactors = FALSE
      )
      point <- point[order(point$sample), , drop = FALSE]
      channelPieces[[j]] <- point
    }

    pieces[[i]] <- do.call(rbind, channelPieces)
  }

  out <- do.call(rbind, pieces)
  row.names(out) <- NULL
  out[order(match(out$channel, channels), out$sample), , drop = FALSE]
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

#' Read the appropriate data for a viewport
#'
#' @param cache A `StudyCache`.
#' @inheritParams read_study_signal
#' @param channels Channel labels or indices.
#' @param pixel_width Plot width in device pixels.
#' @param resolution `"auto"`, `"raw"`, or `"overview"`.
#' @param points_per_pixel Target maximum rendered points per pixel.
#' @param units Raw read units.
#' @return A list with `data`, `resolution`, and `level`.
#' @export
read_study_viewport <- function(cache,
                                begin = NULL,
                                end = NULL,
                                interval = NULL,
                                channels = NULL,
                                pixel_width,
                                resolution = c("auto", "raw", "overview"),
                                points_per_pixel = 4,
                                units = c("physical", "digital")) {
  resolution <- match.arg(resolution)
  units <- match.arg(units)
  window <- gm_normalize_study_window(cache, begin, end, interval)
  windowSeconds <- window$end - window$begin

  if (resolution == "overview" && !cache_is_built(cache)) {
    stop("cache not built yet; run build_study_cache() first", call. = FALSE)
  }

  if (resolution == "raw" || !cache_is_built(cache) || windowSeconds <= 0) {
    return(list(
      data = read_study_signal(
        cache = cache,
        begin = begin,
        end = end,
        interval = interval,
        channels = channels,
        units = units
      ),
      resolution = "raw",
      level = 0L
    ))
  }

  selected <- select_cache_level(
    cache,
    window_seconds = windowSeconds,
    pixel_width = pixel_width,
    points_per_pixel = points_per_pixel
  )

  if (resolution == "auto" && selected$level[[1L]] == 0L) {
    return(list(
      data = read_study_signal(
        cache = cache,
        begin = begin,
        end = end,
        interval = interval,
        channels = channels,
        units = units
      ),
      resolution = "raw",
      level = 0L
    ))
  }

  if (resolution == "overview" && selected$level[[1L]] == 0L) {
    overview <- cache@levels[cache@levels$level > 0L, , drop = FALSE]
    selected <- overview[which.min(overview$bucket_seconds), , drop = FALSE]
  }

  list(
    data = read_cache_overview(
      cache = cache,
      begin = begin,
      end = end,
      interval = interval,
      channels = channels,
      level = selected$level[[1L]],
      pixel_width = pixel_width,
      points_per_pixel = points_per_pixel
    ),
    resolution = selected$bucket_samples[[1L]],
    level = selected$level[[1L]]
  )
}

#' Visible window implied by a sweep speed
#'
#' @param sweep_speed_mm_s Sweep speed in millimetres per second.
#' @param screen_width_mm Physical plot width in millimetres.
#' @return Visible window in seconds.
#' @export
sweep_window_seconds <- function(sweep_speed_mm_s, screen_width_mm = 500) {
  screen_width_mm / sweep_speed_mm_s
}
