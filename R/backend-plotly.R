# Everything specific to the plotly backend: the spec R builds for it, and the
# one-call viewer that exercises it. The browser side is
# inst/htmlwidgets/lib/gram/gram-adapter-plotly.js.
#
# plotly is declarative, so nearly the whole figure is decided here -- traces,
# axes, the grid, the gestures allowed -- and the adapter has little to add
# beyond the element's width and two event listeners. Compare gm_build_uplot_spec(),
# where an imperative library keeps most of the work in JavaScript. Every
# choice below was checked against plotly.js 2.25.2, the bundle {plotly}
# ships; where a behaviour is decided by a particular line of that source, the
# comment names it.
#
# The bundle is borrowed from {plotly} rather than vendored: 3.5 MB is the
# cost of a plotly widget, paid only when one is drawn.

#' Build the plotly spec for a set of panels
#'
#' @param panels Validated panels, as `gm_validate_panels()` returns them.
#' @param window Loaded range, `list(min =, max =)`; becomes the forced x
#'   range.
#' @param scale X-scale description; `kind` picks the axis title.
#' @param panel_height Height of each subplot row in CSS pixels.
#' @return A list holding `data` (one `scattergl` trace per panel), `layout`
#'   (a coupled grid, one shared x axis, one fixed y axis per row) and
#'   `config` -- the three arguments of `Plotly.react()`. Width is not set;
#'   the adapter measures it.
#' @keywords internal
#' @noRd
gm_build_plotly_spec <- function(panels, window, scale, panel_height) {
  n <- length(panels)
  yaxis <- function(i) paste0("y", if (i > 1L) i else "")

  traces <- lapply(seq_len(n), function(i) {
    list(
      type = "scattergl",   # WebGL; one regl context per figure, not per row
      mode = "lines",
      hoverinfo = "none",   # keeps the spike line, drops one hover label per row
      x = panels[[i]]$x,
      y = panels[[i]]$y,
      xaxis = "x",
      yaxis = yaxis(i),
      line = list(color = panels[[i]]$color %||% "#111", width = 1)
    )
  })

  margin <- list(l = 72, r = 8, t = 8, b = 32)
  layout <- list(
    # One shared x axis over stacked rows. `coupled` generates y, y2, ..., yn
    # top to bottom and anchors x to the bottom row that has a subplot
    # (grid/index.js L297-336), so the x ticks move when the bottom channel is
    # hidden -- what the uPlot adapter does by hand.
    grid = list(rows = n, columns = 1L, pattern = "coupled", ygap = 0.08),
    margin = margin,
    showlegend = FALSE,
    # width is the adapter's: R does not know the element's box
    height = n * panel_height + margin$t + margin$b,
    dragmode = "zoom",
    hovermode = "x",
    xaxis = list(
      # Forced. With no uirevision, Plotly.react resets to this range rather
      # than keeping the reader's zoom (plot_api.js L2473-2530), which is what
      # makes a push land where R said.
      range = c(window$min, window$max),
      title = list(
        text = switch(scale$kind, elapsed = "Time (s)", index = "Sample", "")
      ),
      # the shared cursor: in 2.25 an `across` spike spans every y axis
      # anchored to x, i.e. the whole stack (hover.js L2089-2097)
      showspikes = TRUE,
      spikemode = "across",
      spikesnap = "cursor",
      spikethickness = 1
    )
  )
  for (i in seq_len(n)) {
    layout[[paste0("yaxis", if (i > 1L) i else "")]] <- list(
      # every y fixed makes the drag box zoom x only (dragbox.js L401-419)
      fixedrange = TRUE,
      title = list(text = panels[[i]]$label %||% "")
    )
  }

  list(
    data = traces,
    layout = layout,
    # Exactly uPlot's gesture surface and nothing more: no modebar buttons, no
    # double-click autorange, no wheel zoom (the adapter owns the wheel and
    # pans with it), no axis-strip drag handles.
    config = list(
      displayModeBar = FALSE,
      doubleClick = FALSE,
      scrollZoom = FALSE,
      showAxisDragHandles = FALSE,
      responsive = FALSE
    )
  )
}

#' View a study window with plotly
#'
#' Reads one window from a `StudyCache` and returns the plotly widget: cache
#' and window in, widget out, no controller. It is the one-call check that
#' this backend draws a window, and it lives beside the spec it exercises.
#' Needs the `plotly` package, whose plotly.js bundle is borrowed rather than
#' vendored.
#'
#' The window is given in samples, the same currency [read_viewport()] and
#' [normalize_selection()] speak. The whole record is a valid window and the
#' default.
#'
#' @inheritParams view_uplot
#' @return An `htmlwidget`.
#' @family backend viewers
#' @seealso [view_uplot()], [gram_plot()]
#' @keywords internal
#' @export
view_plotly <- function(cache,
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
    backend = "plotly",
    scale = list(kind = "elapsed", unit = "s"),
    width = width,
    height = height
  )
}
