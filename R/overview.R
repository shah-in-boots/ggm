# overview.R -----------------------------------------------------------
# The overview pyramid: build it, and read one level of it back
#
# The overview is min/max per channel per bucket, with the sample index of
# each extremum, at bucket sizes 64, 256, 1024, ... up to one that covers the
# record. Levels above the first are built by merging the level below, so the
# raw signal is streamed exactly once. Raw viewport reads still go through
# EGM::read_signal(), which seeks into the .dat file.
#
# build_overview() writes the table and read_viewport() reads it back, and
# they live together because they are the writer and the reader of one
# on-disk format: the `ch<i>.min_at` column naming, the bucket geometry, and
# the manifest's `buckets` vector mean the same thing in both.
#
# The dependency runs one way. This file calls into R/cache.R for the handle,
# gm_manifest(), read_study_signal(), and gm_cache_channel_index(); nothing
# in R/cache.R calls back into here.

# design.qmd latency target: no more than four plotted points per pixel per
# channel. Each bucket contributes two points, a minimum and a maximum.
gm_points_per_pixel <- 4

gm_bucket_base <- 64L
gm_bucket_factor <- 4L


# overview build --------------------------------------------------------

#' Reduce a signal to per-bucket extrema
#'
#' Splits `values` into consecutive runs of `bucket` and returns the minimum
#' and maximum of each run together with the sample index at which each
#' occurred. It serves the first overview level, where `values` is raw signal,
#' and every merge above it, where `values` is the level below's minima or
#' maxima and `samples` their positions.
#'
#' @param values Numeric vector.
#' @param samples Integer vector, the sample index of each value.
#' @param bucket Number of consecutive values per bucket.
#' @return A data frame with one row per bucket and columns `min`, `min_at`,
#'   `max`, `max_at`. A bucket containing `NA` reports `NA`, so a gap in the
#'   signal stays a gap in the overview.
#' @keywords internal
gm_bucket_extrema <- function(values, samples, bucket) {
  # Pad a partial last bucket by repeating its final element. This is safe
  # only because the real sample precedes its copies and ties.method = "first"
  # keeps the earlier one. NA padding is not an option: max.col() returns NA
  # for any row holding NA.
  pad <- (-length(values)) %% bucket
  values <- c(values, rep(values[length(values)], pad))
  samples <- c(samples, rep(samples[length(samples)], pad))

  # ponytail: base R at about 5 s for a 2.7 h, 27 channel record, against
  # 30 s spent reading it. Move to cpp11 only if a record measures slow here.
  m <- matrix(values, ncol = bucket, byrow = TRUE)
  s <- matrix(samples, ncol = bucket, byrow = TRUE)
  rows <- seq_len(nrow(m))
  lo <- max.col(-m, ties.method = "first")
  hi <- max.col(m, ties.method = "first")

  data.frame(
    min = m[cbind(rows, lo)],
    min_at = s[cbind(rows, lo)],
    max = m[cbind(rows, hi)],
    max_at = s[cbind(rows, hi)]
  )
}

#' Build the overview cache for a study
#'
#' Streams the record through [read_viewport()] in chunks, reduces each chunk
#' to per-bucket minima and maxima with [gm_bucket_extrema()], merges the
#' result upward until one bucket covers the whole record, and writes the
#' stacked levels beside the record as `<stem>.gram.parquet` (or `.rds`) with
#' a `cache` section in `<stem>.gram.json`. Peak memory is one chunk, not the
#' record.
#'
#' The table has one row per bucket and columns `level`, `start` (first
#' sample of the bucket) and, per channel position `i`, `ch<i>.min`,
#' `ch<i>.min_at`, `ch<i>.max`, `ch<i>.max_at`. Values are in physical units.
#' Time is never stored; it is `sample / sample_rate`.
#'
#' @param cache A `StudyCache` from [study_cache()].
#' @param chunk_seconds Seconds of signal read per pass. Bounds memory during
#'   the build; it does not change the result.
#' @param format On-disk format of the table. Parquet reads a subset of
#'   channels without touching the rest, which is what keeps a viewport read
#'   fast; rds reads everything.
#' @param rebuild Build even when a usable overview already exists.
#' @return The handle, invisibly. The overview lives on disk, not in the
#'   handle, so no reassignment is needed.
#' @seealso [read_viewport()]
#' @family viewport
#' @export
build_overview <- function(cache,
                           chunk_seconds = 60,
                           format = c("parquet", "rds"),
                           rebuild = FALSE) {
  format <- match.arg(format)
  if (!is.numeric(chunk_seconds) || length(chunk_seconds) != 1L ||
        !is.finite(chunk_seconds) || chunk_seconds <= 0) {
    stop("`chunk_seconds` must be a single positive number", call. = FALSE)
  }
  if (!is.finite(cache@sample_rate) || cache@sample_rate <= 0) {
    stop("the WFDB header has no usable sampling frequency", call. = FALSE)
  }
  # a header may omit the count, and EGM then reads to .Machine$integer.max
  if (!is.finite(cache@n_samples) || cache@n_samples < 1) {
    stop("the WFDB header has no usable sample count", call. = FALSE)
  }
  if (!rebuild && !is.null(gm_manifest(cache))) {
    message("overview already built (rebuild = TRUE to build again)")
    return(invisible(cache))
  }

  cacheDir <- dirname(cache@manifest_path)
  dir.create(cacheDir, recursive = TRUE, showWarnings = FALSE)
  if (file.access(cacheDir, mode = 2L) != 0L) {
    stop(
      "cache directory is not writable: ", cacheDir,
      "; open the study with `cache_dir` pointing somewhere writable",
      call. = FALSE
    )
  }

  nSamples <- as.integer(cache@n_samples)
  nChannels <- length(cache@channels)
  columns <- function(i, stat) paste0("ch", i, ".", stat)

  # level 1 straight from the signal, one chunk at a time. The chunk is a
  # multiple of the bucket so no bucket straddles two chunks.
  chunkSamples <- max(
    gm_bucket_base,
    (as.integer(chunk_seconds * cache@sample_rate) %/% gm_bucket_base) * gm_bucket_base
  )
  starts <- seq.int(0L, nSamples - 1L, by = chunkSamples)
  pieces <- lapply(starts, function(start) {
    finish <- min(start + chunkSamples, nSamples)
    raw <- read_viewport(cache, list(begin = start, end = finish), resolution = "raw")$data
    perChannel <- lapply(seq_len(nChannels), function(i) {
      extrema <- gm_bucket_extrema(raw[[i + 1L]], raw$sample, gm_bucket_base)
      names(extrema) <- columns(i, names(extrema))
      extrema
    })
    rows <- nrow(perChannel[[1L]])
    do.call(cbind, c(
      list(data.frame(
        level = 1L,
        start = as.integer(seq.int(start, by = gm_bucket_base, length.out = rows))
      )),
      perChannel
    ))
  })
  level <- do.call(rbind, pieces)
  row.names(level) <- NULL

  # each level above merges `gm_bucket_factor` rows of the one below, keeping
  # the minimum of the minima and the maximum of the maxima with its position
  levels <- list(level)
  buckets <- gm_bucket_base
  while (nrow(level) > 1L) {
    bucket <- buckets[length(buckets)] * gm_bucket_factor
    perChannel <- lapply(seq_len(nChannels), function(i) {
      lo <- gm_bucket_extrema(level[[columns(i, "min")]], level[[columns(i, "min_at")]], gm_bucket_factor)
      hi <- gm_bucket_extrema(level[[columns(i, "max")]], level[[columns(i, "max_at")]], gm_bucket_factor)
      stats::setNames(
        data.frame(lo$min, lo$min_at, hi$max, hi$max_at),
        columns(i, c("min", "min_at", "max", "max_at"))
      )
    })
    rows <- nrow(perChannel[[1L]])
    level <- do.call(cbind, c(
      list(data.frame(
        level = length(levels) + 1L,
        start = as.integer(seq.int(0L, by = bucket, length.out = rows))
      )),
      perChannel
    ))
    levels[[length(levels) + 1L]] <- level
    buckets <- c(buckets, bucket)
  }
  overview <- do.call(rbind, levels)
  row.names(overview) <- NULL

  # publish the table, then the manifest: the cache section is the completion
  # marker, so a build that dies half way leaves nothing that looks usable
  dataFile <- paste0(cache@stem, ".gram.", format)
  dataTmp <- tempfile(pattern = paste0(cache@stem, ".gram-"), tmpdir = cacheDir)
  on.exit(unlink(dataTmp), add = TRUE)
  if (format == "parquet") {
    nanoparquet::write_parquet(overview, dataTmp)
  } else {
    saveRDS(overview, dataTmp, compress = FALSE)
  }
  if (!file.rename(dataTmp, file.path(cacheDir, dataFile))) {
    stop("failed to publish the overview table into ", cacheDir, call. = FALSE)
  }

  # the manifest is shared: replace only the cache section and keep the rest
  manifest <- if (file.exists(cache@manifest_path)) {
    jsonlite::read_json(cache@manifest_path)
  } else {
    list()
  }
  manifest$gram <- 1L
  manifest$record <- list(stem = cache@stem, dir = cache@dir)
  manifest$cache <- list(
    version = gm_cache_version,
    algorithm = "bucket-extrema",
    fingerprint = cache@fingerprint,
    file = dataFile,
    format = format,
    units = "physical",
    sample_rate = cache@sample_rate,
    n_samples = cache@n_samples,
    channels = I(cache@channels),
    buckets = I(buckets),
    created_at = strftime(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z", tz = "UTC")
  )
  manifestTmp <- tempfile(pattern = paste0(cache@stem, ".gram-"), tmpdir = cacheDir)
  on.exit(unlink(manifestTmp), add = TRUE)
  jsonlite::write_json(manifest, manifestTmp, auto_unbox = TRUE, digits = NA, pretty = TRUE)
  if (!file.rename(manifestTmp, cache@manifest_path)) {
    stop("failed to publish the manifest ", cache@manifest_path, call. = FALSE)
  }

  invisible(cache)
}


# viewport reads --------------------------------------------------------

#' Read the data needed to draw a window
#'
#' Routes a sample window to the raw signal or to an overview level. Raw is
#' used when the window already holds few enough samples to draw; otherwise
#' the finest overview level that keeps the plotted points near the design's
#' four per pixel per channel. An overview is never used for measurement or
#' snapping; it is for drawing.
#'
#' @param cache A `StudyCache`.
#' @param window A list holding `begin` and `end` sample indices delimiting a
#'   half-open range, as [normalize_selection()] returns.
#' @param channels Channel labels or indices. Defaults to all channels.
#' @param width_px Width of the plot in pixels. Required unless
#'   `resolution = "raw"`.
#' @param resolution `"auto"` chooses by window and width, `"raw"` always
#'   reads the signal, and `"overview"` always reads a cache level, the
#'   finest one when the window is small.
#' @return A list with `data`, `resolution`, and `level`. For raw reads
#'   `data` is the signal table (`sample` plus one column per channel),
#'   `resolution` is `"raw"` and `level` is `0`. For overview reads `data` is
#'   a named list with one `list(sample, value)` per channel, the minima and
#'   maxima of each bucket in sample order with a flat bucket's pair collapsed
#'   to one point; `resolution` is the bucket size in samples and `level` its
#'   position in the pyramid. Extrema fall at different samples per channel,
#'   which is why the two shapes differ.
#' @seealso [build_overview()], [read_study_signal()]
#' @family viewport
#' @export
read_viewport <- function(cache,
                          window,
                          channels = NULL,
                          width_px = NULL,
                          resolution = c("auto", "raw", "overview")) {
  resolution <- match.arg(resolution)
  if (!is.list(window) || !all(c("begin", "end") %in% names(window))) {
    stop("`window` must be a list holding `begin` and `end` sample indices", call. = FALSE)
  }
  begin <- window$begin
  end <- window$end
  if (!is.numeric(begin) || !is.numeric(end) || length(begin) != 1L || length(end) != 1L ||
        any(!is.finite(c(begin, end))) || begin != trunc(begin) || end != trunc(end)) {
    stop("`window` must hold two whole-number sample indices", call. = FALSE)
  }
  if (begin < 0 || end > cache@n_samples || begin >= end) {
    stop(
      "`window` must satisfy 0 <= begin < end <= ", format(cache@n_samples, scientific = FALSE),
      ", got begin = ", begin, " and end = ", end,
      call. = FALSE
    )
  }
  if (resolution != "raw" && (!is.numeric(width_px) || length(width_px) != 1L ||
                                !is.finite(width_px) || width_px <= 0)) {
    stop("`width_px` must be a single positive number unless resolution = \"raw\"", call. = FALSE)
  }
  index <- gm_cache_channel_index(cache, channels)
  span <- end - begin

  if (resolution == "raw" || (resolution == "auto" && span <= gm_points_per_pixel * width_px)) {
    # EGM takes times, not samples, and rounds elapsed seconds to nine digits
    # before ceiling(): sample k sent as k / rate comes back as k + 1 for
    # about two thirds of k at 977 Hz. Half a sample early lands on k every
    # time. The check below is what fails if that ever stops being true.
    startTime <- attr(cache@header, "record_line")$start_time
    asTime <- function(sample) {
      seconds <- max(sample - 0.5, 0) / cache@sample_rate
      if (inherits(startTime, "POSIXt") && length(startTime) == 1L && !is.na(startTime)) {
        startTime + seconds
      } else {
        as.difftime(seconds, units = "secs")
      }
    }
    signal <- read_study_signal(
      cache,
      begin = asTime(begin),
      end = asTime(end),
      channels = index
    )
    if (nrow(signal) != span || signal$sample[[1L]] != begin) {
      stop(
        "EGM returned samples ", signal$sample[[1L]], "..",
        signal$sample[[nrow(signal)]], " for the window ", begin, "..", end - 1,
        call. = FALSE
      )
    }
    return(list(data = signal, resolution = "raw", level = 0L))
  }

  section <- gm_manifest(cache)
  if (is.null(section)) {
    stop("overview not built or stale for this record; run build_overview()", call. = FALSE)
  }
  buckets <- as.integer(section$buckets)
  # each bucket draws two points, so a bucket must hold at least
  # 2 * span / (points per pixel * width) samples
  usable <- which(2 * span / buckets <= gm_points_per_pixel * width_px)
  level <- if (length(usable) > 0L) usable[[1L]] else length(buckets)
  bucket <- buckets[[level]]

  columns <- as.vector(t(outer(paste0("ch", index), c(".min", ".min_at", ".max", ".max_at"), paste0)))
  dataPath <- file.path(dirname(cache@manifest_path), section$file)
  overview <- if (identical(section$format, "parquet")) {
    nanoparquet::read_parquet(dataPath, col_select = c("level", "start", columns))
  } else {
    readRDS(dataPath)[, c("level", "start", columns)]
  }
  rows <- overview[overview$level == level & overview$start < end & overview$start + bucket > begin, , drop = FALSE]

  data <- lapply(index, function(i) {
    sample <- c(rows[[paste0("ch", i, ".min_at")]], rows[[paste0("ch", i, ".max_at")]])
    value <- c(rows[[paste0("ch", i, ".min")]], rows[[paste0("ch", i, ".max")]])
    ordering <- order(sample)
    sample <- sample[ordering]
    value <- value[ordering]
    keep <- !duplicated(sample)
    list(sample = sample[keep], value = value[keep])
  })
  names(data) <- cache@channels[index]

  list(data = data, resolution = bucket, level = level)
}
