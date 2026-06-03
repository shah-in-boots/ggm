# The windowed-read router (blueprint S3.4).
#
# `get_window()` is the single surface renderers read through. It takes a time
# window in *seconds*, does its work in *samples*, and returns data carrying
# both (the S3.0 boundary in practice: renderers join annotations on `sample`
# and label their axis in `time`).
#
# Spine status: only the raw `.dat` path exists. When points-per-pixel is high
# the router will instead serve a downsampled signal-pyramid tier (milestone
# M0); `.select_tier()` is where that decision will live. For now it always
# returns "raw", so behaviour is correct (just not yet fast at full zoom-out).

#' Read a window of signal
#'
#' The adaptive windowed read that feeds the renderers. Give it a time window
#' (seconds) and the channels you want; it returns those channels over that
#' window with both `sample` and `time` columns.
#'
#' @param study A `ggm_study` from [open_study()].
#' @param channels Character vector of channel labels to read. `NULL` (default)
#'   reads every channel in the study.
#' @param begin,end Window bounds in **seconds**. `end = NA` (default) reads to
#'   the end of the record.
#' @param px_width Width of the target viewport in pixels. Optional; when given,
#'   it is used to compute points-per-pixel and (in a future milestone) choose a
#'   downsampled tier. It does not change the data in this spine release.
#' @param units `"physical"` (mV, default — what you plot) or `"digital"` (raw
#'   ADC integers). Passed through to [EGM::read_signal()].
#'
#' @return A `ggm_window`: an `EGM` `signal_table` (a `data.table`) with a
#'   `sample` column, a `time` column (seconds), and one column per requested
#'   channel. Carries attributes `tier` (which source served it — `"raw"` for a
#'   direct `.dat` read), `ppp` (points-per-pixel, or `NA`), and `frequency`.
#'
#' @examples
#' \dontrun{
#' study <- open_study("bard-egm", system.file("extdata", package = "ggm"))
#' w <- get_window(study, channels = c("HIS D", "RV 1-2"), begin = 1, end = 2)
#' attr(w, "tier")
#' }
#' @export
get_window <- function(study, channels = NULL, begin = 0, end = NA,
                       px_width = NULL, units = c("physical", "digital")) {
  if (!is_study(study)) {
    stop("`study` must be a `ggm_study` (see `open_study()`).", call. = FALSE)
  }
  units <- match.arg(units)
  fs <- study$frequency

  channels <- resolve_channels(channels, study$channels)

  # Effective end for window math / ppp: an open end means "to the record's end".
  end_eff <- if (is.na(end)) study$duration else end
  if (end_eff <= begin) {
    stop("`end` must be greater than `begin`.", call. = FALSE)
  }

  ppp <- points_per_pixel(begin, end_eff, fs, px_width)
  tier <- .select_tier(ppp, study$pyramid, units)

  out <- if (identical(tier, "raw")) {
    read_window_raw(study, channels, begin, end, units)
  } else {
    read_window_tier(study, channels, begin, end_eff, tier, fs)
  }

  class(out) <- c("ggm_window", class(out))
  attr(out, "tier") <- tier
  attr(out, "ppp") <- ppp
  attr(out, "frequency") <- fs
  attr(out, "window") <- c(begin = begin, end = end_eff)
  out
}

# Full-resolution path: a direct byte-seek range read from the `.dat` via EGM.
# All channels share one sample grid, so no gaps.
read_window_raw <- function(study, channels, begin, end, units) {
  out <- EGM::read_signal(
    record = study$record, record_dir = study$record_dir,
    begin = begin, end = end, channels = channels, units = units
  )
  data.table::set(out, j = "time", value = sample_to_time(out[["sample"]], study$frequency))
  data.table::setcolorder(out, c("sample", "time", channels))
  out
}

# Overview path: read the requested channels' LTTB points for `tier` from the
# Parquet sidecar and restrict to the window. Each channel was reduced
# independently, so they land on different sample indices; we union them onto a
# shared `sample` grid (NA where a channel has no point), which is exactly the
# columnar gap form renderers expect.
read_window_tier <- function(study, channels, begin, end, tier, fs) {
  pyramid <- study$pyramid
  s0 <- time_to_sample(begin, fs)
  s1 <- time_to_sample(end, fs)
  ids <- pyramid$manifest$channels
  id_for <- stats::setNames(ids$id, ids$label)

  parts <- lapply(channels, function(label) {
    p <- file.path(
      pyramid$path, "signal",
      paste0("channel=", id_for[[label]]),
      paste0("tier=", tier), "part.parquet"
    )
    dt <- data.table::as.data.table(arrow::read_parquet(p, col_select = c("sample", "value")))
    dt <- dt[dt$sample >= s0 & dt$sample <= s1]
    dt$channel <- label
    dt
  })
  long <- data.table::rbindlist(parts)

  if (nrow(long) == 0L) {
    # Window falls between this tier's points; return an empty but well-formed frame.
    out <- data.table::data.table(sample = integer(), time = double())
    for (ch in channels) out[, (ch) := double()]
    return(out)
  }

  out <- data.table::dcast(long, sample ~ channel, value.var = "value")
  # dcast drops channels with no points in range; add them back as all-NA.
  for (ch in setdiff(channels, names(out))) out[, (ch) := NA_real_]
  data.table::set(out, j = "time", value = sample_to_time(out[["sample"]], fs))
  data.table::setcolorder(out, c("sample", "time", channels))
  out[order(out$sample)]
}

#' @export
print.ggm_window <- function(x, ...) {
  win <- attr(x, "window")
  cat(sprintf(
    "<ggm_window> tier=%s · %s samples × %d channels · %.3f–%.3f s",
    attr(x, "tier"),
    format(nrow(x), big.mark = ","),
    sum(!names(x) %in% c("sample", "time")),
    win[["begin"]], win[["end"]]
  ))
  ppp <- attr(x, "ppp")
  if (!is.na(ppp)) cat(sprintf(" · ppp=%.1f", ppp))
  cat("\n")
  NextMethod()
}

# ---- internals --------------------------------------------------------------

# Validate/default the requested channels against what the study actually has.
resolve_channels <- function(channels, available) {
  if (is.null(channels)) return(available)
  if (!is.character(channels)) {
    stop("`channels` must be a character vector of channel labels.", call. = FALSE)
  }
  missing <- setdiff(channels, available)
  if (length(missing)) {
    stop(
      "Unknown channel(s): ", paste(missing, collapse = ", "),
      "\n  available: ", paste(available, collapse = ", "),
      call. = FALSE
    )
  }
  channels
}

# Points-per-pixel: how many source samples fall under one screen pixel. This is
# the number the tier router keys off. NA when we don't know the viewport width.
points_per_pixel <- function(begin, end, frequency, px_width) {
  if (is.null(px_width) || is.na(px_width) || px_width <= 0) return(NA_real_)
  n_samples <- (end - begin) * frequency
  n_samples / px_width
}

# Tier selection. Returns "raw" (direct .dat read) unless a pyramid is bound and
# the zoom is coarse enough to use a tier. The pyramid stores physical units, so
# digital requests always stay raw. Among eligible tiers (bucket size <= ppp, so
# never undersampled) the coarsest is chosen — the smallest payload that still
# yields about one point per pixel.
.select_tier <- function(ppp, pyramid = NULL, units = "physical") {
  if (is.null(pyramid) || is.na(ppp) || units != "physical") return("raw")
  tiers <- pyramid$manifest$tiers
  eligible <- tiers$samples_per_bucket[tiers$use_when_ppp_above <= ppp]
  if (length(eligible) == 0L) return("raw")
  max(eligible)
}
