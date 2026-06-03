# The signal pyramid (blueprint S3.2, milestone M0).
#
# The pyramid is the precomputed, downsampled overview the raw `.dat` cannot
# give cheaply ("all of channel 1 at once"). `build_pyramid()` reads each
# channel at full resolution once, LTTB-reduces it at several zoom tiers, and
# writes the result to a regenerable Parquet sidecar next to the record, plus a
# manifest the router (`get_window()`) consults to pick a tier.
#
# Two stores, two jobs: the `.dat` answers "this window, full detail"; the
# pyramid answers "the whole study, in shape". The same samples never live in
# both.

#' Build the signal pyramid
#'
#' Compute LTTB-downsampled overview tiers for every channel and write them,
#' with a manifest, to a Parquet sidecar (`<record>.ggm-pyramid/`) alongside the
#' WFDB files. Once built, [open_study()] binds it automatically and
#' [get_window()] serves a tier (instead of a raw read) when zoomed far out.
#'
#' @param study A `ggm_study` from [open_study()].
#' @param tiers Integer vector of downsample ratios (samples per LTTB bucket).
#'   Each becomes one tier; coarser tiers are tiny. Defaults to 1:10 ... 1:10000.
#' @param envelope Whether to also store per-bucket min/max envelopes, so sharp
#'   deflections are never visually dropped at extreme zoom-out.
#' @param overwrite Rebuild even if a sidecar already exists.
#'
#' @return The sidecar directory path, invisibly. Reopen the study (or call
#'   [open_study()] again) to bind the freshly built pyramid.
#'
#' @details
#' The sidecar layout matches the blueprint schema:
#' \preformatted{
#'   <record>.ggm-pyramid/
#'     manifest.json
#'     signal/channel=<id>/tier=<N>/part.parquet   # sample, value[, vmin, vmax]
#' }
#' Values are stored in physical units (mV). The build reads one channel at a
#' time to keep memory bounded on multi-hour records.
#'
#' @examples
#' \dontrun{
#' study <- open_study("bard-egm", system.file("extdata", package = "ggm"))
#' build_pyramid(study, tiers = c(10, 100))
#' study <- open_study("bard-egm", system.file("extdata", package = "ggm")) # now bound
#' }
#' @export
build_pyramid <- function(study, tiers = c(10, 100, 1000, 10000),
                          envelope = TRUE, overwrite = FALSE) {
  if (!is_study(study)) {
    stop("`study` must be a `ggm_study` (see `open_study()`).", call. = FALSE)
  }
  tiers <- sort(unique(as.integer(tiers)))
  if (any(is.na(tiers)) || any(tiers < 2L)) {
    stop("`tiers` must be integers >= 2 (samples per bucket).", call. = FALSE)
  }

  dir <- pyramid_path(study)
  if (dir.exists(dir)) {
    if (!overwrite) {
      stop(
        "A pyramid already exists at ", dir,
        "\n  pass `overwrite = TRUE` to rebuild.",
        call. = FALSE
      )
    }
    unlink(dir, recursive = TRUE)
  }

  header <- study$header
  ids <- as.integer(header$number)
  labels <- as.character(header$label)
  units <- as.character(header$ADC_units)[1]
  if (is.na(units) || !nzchar(units)) units <- "mV"

  # Reduce each channel at every tier and write one part file per (channel, tier).
  n_points <- integer(length(tiers))
  for (j in seq_along(labels)) {
    sig <- EGM::read_signal(
      record = study$record, record_dir = study$record_dir,
      channels = labels[j], units = "physical"
    )
    s <- sig[["sample"]]
    v <- sig[[labels[j]]]

    for (t in seq_along(tiers)) {
      threshold <- max(2L, as.integer(ceiling(length(v) / tiers[t])))
      red <- lttb_reduce(s, v, threshold, envelope = envelope)
      part_dir <- file.path(
        dir, "signal",
        paste0("channel=", ids[j]),
        paste0("tier=", tiers[t])
      )
      dir.create(part_dir, recursive = TRUE, showWarnings = FALSE)
      arrow::write_parquet(red, file.path(part_dir, "part.parquet"))
      if (j == 1L) n_points[t] <- nrow(red)
    }
  }

  manifest <- list(
    sampling_frequency = study$frequency,
    n_samples = study$n_samples,
    units = units,
    envelope = envelope,
    created = format(Sys.time(), tz = "UTC", usetz = TRUE),
    channels = data.frame(id = ids, label = labels, stringsAsFactors = FALSE),
    tiers = data.frame(
      id = tiers,
      samples_per_bucket = tiers,
      n_points = n_points,
      # The router uses this tier once points-per-pixel reaches its bucket size,
      # i.e. when the tier yields about one point per pixel or denser.
      use_when_ppp_above = tiers,
      stringsAsFactors = FALSE
    )
  )
  write_manifest(manifest, file.path(dir, "manifest.json"))

  message(sprintf(
    "Built pyramid: %d channels x %d tiers -> %s",
    length(labels), length(tiers), dir
  ))
  invisible(dir)
}

# ---- sidecar location + manifest I/O ---------------------------------------

# Sidecar directory for a study's pyramid (next to the .dat/.hea).
pyramid_path <- function(study) {
  file.path(study$record_dir, paste0(study$record, ".ggm-pyramid"))
}

write_manifest <- function(manifest, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(manifest, path, auto_unbox = TRUE, pretty = TRUE, dataframe = "rows")
}

# Read a manifest back into a list. `channels` and `tiers` come back as
# data.frames (column-oriented JSON), which is what `.select_tier()` expects.
read_manifest <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}

# Bind an existing pyramid to a study on open, or NULL if none is built yet.
bind_pyramid <- function(record, record_dir) {
  dir <- file.path(record_dir, paste0(record, ".ggm-pyramid"))
  manifest_file <- file.path(dir, "manifest.json")
  if (!file.exists(manifest_file)) return(NULL)
  list(path = dir, manifest = read_manifest(manifest_file))
}
