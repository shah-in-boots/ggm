# Cache to panels. gm_read_panels() is the seam: it turns whichever shape
# read_viewport() hands back into the backend-neutral panels every renderer
# starts from, so a backend never learns whether it is drawing raw samples or
# bucket extrema. Each backend's viewer -- view_uplot() and its siblings --
# begins here.

#' Read a viewport and shape it for a renderer
#'
#' Reads one window through [read_viewport()] and flattens both of its return
#' shapes -- the raw signal table and the per-channel overview extrema -- into
#' one list of panels with `x` in elapsed seconds. Panels from an overview tier
#' differ in length, because each channel's extrema fall on its own samples.
#'
#' @inheritParams read_viewport
#' @return A list holding `panels`, the `window` and `extent` as
#'   `list(min =, max =)` in elapsed seconds, the `resolution` and `level`
#'   reported by [read_viewport()].
#' @keywords internal
#' @noRd
gm_read_panels <- function(cache,
                               window,
                               channels = NULL,
                               width_px = 1200,
                               resolution = c("auto", "raw", "overview")) {
  view <- read_viewport(
    cache = cache,
    window = window,
    channels = channels,
    width_px = width_px,
    resolution = match.arg(resolution)
  )

  rate <- cache@sample_rate
  labels <- cache@channels[gm_match_channels(channels, cache@channels)]

  # Index both branches positionally, never by label. EGM::read_signal() names
  # signal columns from the header, so a record carrying two channels with the
  # same label yields duplicate names and a lookup by label reads the wrong
  # one. build_overview() indexes its raw chunks the same way.
  panels <- if (identical(view$resolution, "raw")) {
    seconds <- view$data$sample / rate
    lapply(seq_along(labels), function(i) {
      list(label = labels[[i]], x = seconds, y = view$data[[i + 1L]])
    })
  } else {
    lapply(seq_along(labels), function(i) {
      list(
        label = labels[[i]],
        x = view$data[[i]]$sample / rate,
        y = view$data[[i]]$value
      )
    })
  }

  list(
    panels = panels,
    window = list(min = window$begin / rate, max = window$end / rate),
    extent = list(min = 0, max = cache@n_samples / rate),
    resolution = view$resolution,
    level = view$level
  )
}
