# Everything specific to the uPlot backend: the spec R builds for it, and the
# one-call viewer that exercises it. The browser side is
# inst/htmlwidgets/lib/gram/gram-adapter-uplot.js.
#
# uPlot is imperative. Its options carry functions -- the hooks that keep the
# panels in step, the cursor sync -- which cannot be serialised from R. So the
# spec holds what R can decide and nothing more: the per-panel data, labels
# and strokes, the axis label, the sizes. Small on purpose; compare
# gm_build_plotly_spec(), where a declarative library lets R say nearly everything.

#' Build the uPlot spec for a set of panels
#'
#' @param panels Validated panels, as `gm_validate_panels()` returns them.
#' @param window Loaded range, `list(min =, max =)`. Unused here: the adapter
#'   reads it from the payload, where it stays backend-neutral.
#' @param scale X-scale description; `kind` picks the axis label.
#' @param panel_height Height of each panel in CSS pixels.
#' @return A list the uPlot adapter reads: `panels`, each holding `label`,
#'   `stroke`, `x`, `y`; `x_axis_label`; `x_is_time`; `y_axis_size`;
#'   `panel_height`.
#' @keywords internal
#' @noRd
gm_build_uplot_spec <- function(panels, window, scale, panel_height) {
  list(
    panels = lapply(panels, function(panel) {
      list(
        label = panel$label %||% "",
        stroke = panel$color %||% "#111",
        x = panel$x,
        y = panel$y
      )
    }),
    x_axis_label = switch(scale$kind, elapsed = "Time (s)", index = "Sample", NULL),
    x_is_time = identical(scale$kind, "timestamp"),
    y_axis_size = 72,
    panel_height = as.double(panel_height)
  )
}

#' View a study window with uPlot
#'
#' Reads one window from a `StudyCache` and returns the uPlot widget: cache and
#' window in, widget out, no controller. It is the one-call check that this
#' backend draws a window, and it lives beside the spec it exercises.
#'
#' The window is given in samples, the same currency [read_viewport()] and
#' [normalize_selection()] speak, so a selection made in the viewer can be fed
#' straight back without conversion. The whole record is a valid window; at a
#' coarse overview tier that is the study navigator, so the default shows the
#' entire study rather than an arbitrary opening slice.
#'
#' @inheritParams read_viewport
#' @param cache A `StudyCache` created by [study_cache()].
#' @param window Sample range as `list(begin =, end =)`, half-open. Defaults to
#'   the whole record.
#' @param channels Channel labels or indices. Defaults to all channels.
#' @param width,height Optional widget dimensions.
#' @return An `htmlwidget`.
#' @family backend viewers
#' @seealso [gram_plot()], [read_viewport()]
#' @keywords internal
#' @export
view_uplot <- function(cache,
                       window = NULL,
                       channels = NULL,
                       width_px = 1200,
                       resolution = c("auto", "raw", "overview"),
                       width = NULL,
                       height = 500) {
  window <- window %||% list(begin = 0, end = cache@n_samples)
  view <- gm_read_panels(
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
    backend = "uplot",
    scale = list(kind = "elapsed", unit = "s"),
    width = width,
    height = height
  )
}
