# backend_uplot.R -- uPlot implementation of the plotting contract
#
# only file (plus its JS adapter) that knows uPlot exists.
# swapping backends = new backend_*.R + ggm-adapter-*.js,
# zero changes to backend.R or shiny modules.

#' Create a uPlot-backed electrogram widget
#'
#' `ggm_plot()` is the low-level plotting primitive. It renders one uPlot per
#' signal channel so each panel has an independent y-scale, while synchronizing
#' the x-range and cursor across panels. Data must already be in uPlot's aligned
#' column format: a list containing one shared x vector followed by one y vector
#' per signal series. Use [view_uplot()] to read and display a raw window from a
#' `StudyCache` directly.
#'
#' @param columns List of numeric vectors in the form
#'   `list(x, channel_1, channel_2, ...)`. All vectors must have equal length.
#' @param scale X-scale description. `kind` may be `"index"` for sample
#'   numbers, `"elapsed"` for elapsed seconds, or `"timestamp"` for Unix
#'   timestamps.
#' @param series Optional list of per-channel display lists. Each entry may
#'   contain `label` and `color`.
#' @param panel_height Height of each channel panel in CSS pixels.
#' @param width,height Optional widget dimensions.
#' @param elementId Optional HTML element id.
#' @return An `htmlwidget`.
#' @export
ggm_plot <- function(
  columns,
  scale = list(kind = "index", rate = 1),
  series = NULL,
  panel_height = 120,
  width = NULL,
  height = NULL,
  elementId = NULL
) {
  columns <- validate_uplot_columns(columns)

  if (
    !is.list(scale) ||
      length(scale$kind) != 1L ||
      !scale$kind %in% c("index", "elapsed", "timestamp")
  ) {
    stop(
      "`scale` must be a list whose `kind` is one of ",
      '"index", "elapsed", or "timestamp"',
      call. = FALSE
    )
  }

  # default series config: one entry per non-x column
  n_ch <- length(columns) - 1L
  if (is.null(series)) {
    series <- lapply(seq_len(n_ch), function(i) {
      list(label = paste0("ch", i))
    })
  }
  if (
    !is.list(series) ||
      length(series) != n_ch ||
      any(!vapply(series, function(x) is.list(x) && !is.null(x), logical(1)))
  ) {
    stop("`series` must contain one list per signal column", call. = FALSE)
  }

  if (length(panel_height) != 1L || !is.finite(panel_height) || panel_height < 80) {
    stop("`panel_height` must be a single number of at least 80", call. = FALSE)
  }

  # payload -> renderValue(x) in ggm_plot.js
  # I() keeps length-1 vectors as JSON arrays
  x <- list(
    backend = "uplot",
    columns = lapply(columns, I),
    scale = scale,
    series = series,
    layout = list(
      panel_height = as.double(panel_height)
    )
  )

  htmlwidgets::createWidget(
    name = "ggm_plot",
    x,
    width = width,
    height = height,
    package = "ggm",
    elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(
      browser.fill = TRUE, # fill viewer/browser
      viewer.fill = TRUE
    )
  )
}

validate_uplot_columns <- function(columns) {
  if (!is.list(columns) || length(columns) < 2L) {
    stop("`columns` must be a list containing x and at least one signal", call. = FALSE)
  }
  if (any(!vapply(columns, is.numeric, logical(1)))) {
    stop("every vector in `columns` must be numeric", call. = FALSE)
  }

  lengths <- lengths(columns)
  if (length(unique(lengths)) != 1L) {
    stop("all vectors in `columns` must have equal length", call. = FALSE)
  }
  if (lengths[[1L]] == 0L) {
    stop("`columns` cannot contain empty vectors", call. = FALSE)
  }

  x <- columns[[1L]]
  if (any(!is.finite(x)) || is.unsorted(x, strictly = FALSE)) {
    stop("the x vector must contain finite values in increasing order", call. = FALSE)
  }
  if (any(vapply(columns[-1L], function(x) any(is.infinite(x)), logical(1)))) {
    stop("signal vectors cannot contain infinite values", call. = FALSE)
  }

  unname(columns)
}

# --- shiny bindings (boilerplate, required by htmlwidgets) ------

#' Shiny output binding for a ggm plot
#'
#' @param outputId Output variable to read from.
#' @param width,height Valid CSS dimensions.
#' @return A Shiny widget output element.
#' @export
ggm_plotOutput <- function(outputId, width = "100%",
                           height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "ggm_plot", width, height, package = "ggm"
  )
}

#' Shiny render function for a ggm plot
#'
#' @param expr Expression that produces a [ggm_plot()] widget.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is quoted.
#' @return A Shiny render function.
#' @export
render_ggm_plot <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(
    expr,
    ggm_plotOutput,
    env,
    quoted = TRUE
  )
}
