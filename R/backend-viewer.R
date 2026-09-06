# Cache to picture. gm_viewport_panels() is the seam: it turns whichever shape
# read_viewport() hands back into the backend-neutral panel payload, so a
# renderer never learns whether it is drawing raw samples or bucket extrema.

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
gm_viewport_panels <- function(cache,
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
  labels <- cache@channels[gm_cache_channel_index(cache, channels)]

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

#' View a study window
#'
#' Reads one window from a `StudyCache` and returns the standalone widget.
#' The window is given in samples, the same currency [read_viewport()] and
#' [normalize_selection()] speak, so a selection made in the viewer can be fed
#' straight back without conversion.
#'
#' The whole record is a valid window. At a coarse overview tier that is the
#' study navigator, so the default shows the entire study rather than an
#' arbitrary opening slice.
#'
#' @inheritParams read_viewport
#' @param cache A `StudyCache` created by [study_cache()].
#' @param window Sample range as `list(begin =, end =)`, half-open. Defaults to
#'   the whole record.
#' @param channels Channel labels or indices. Defaults to all channels.
#' @param backend Renderer to draw with. Passed to [gram_plot()].
#' @param width,height Optional widget dimensions.
#' @return An `htmlwidget`.
#' @family backend viewers
#' @seealso [gram_plot()], [read_viewport()]
#' @export
view_uplot <- function(cache,
                       window = NULL,
                       channels = NULL,
                       width_px = 1200,
                       resolution = c("auto", "raw", "overview"),
                       backend = "uplot",
                       width = NULL,
                       height = 500) {
  window <- window %||% list(begin = 0, end = cache@n_samples)
  view <- gm_viewport_panels(
    cache = cache,
    window = window,
    channels = channels,
    width_px = width_px,
    resolution = match.arg(resolution)
  )

  gram_plot(
    panels = view$panels,
    window = view$window,
    extent = view$extent,
    backend = backend,
    scale = list(kind = "elapsed", unit = "s"),
    width = width,
    height = height
  )
}
