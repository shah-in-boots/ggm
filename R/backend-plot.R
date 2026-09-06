# The widget and its payload. Nothing here is uPlot-specific: `gram_plot()`
# validates panels, ships JSON, and names a backend in the payload. Which
# renderer draws it is settled in the browser, by GRAM.adapters[cfg.backend],
# so a second backend is a new adapter in the same bundle rather than a second
# htmlwidget with its own dependency set.
#
# Panels are per-channel rather than one shared x plus aligned y columns. The
# overview tiers built by build_overview() store where each extremum fell
# (`min_at`/`max_at`), so a channel's points land on its own samples and the
# per-channel vectors have different lengths -- 584 to 1168 across one window
# of a 27-channel record. Aligning them is not merely inconvenient, it is only
# possible by unioning every channel's samples into a mostly-empty grid, which
# discards the positions the cache exists to keep. Raw windows simply hand
# every panel the same x vector.

#' Create an electrogram widget
#'
#' `gram_plot()` is the low-level plotting primitive. It renders one panel per
#' signal channel so each has an independent y-scale, while synchronising the
#' x-range and cursor across panels. Each panel carries its own `x` and `y`,
#' which is what lets an overview tier draw its per-channel extrema; panels may
#' differ in length. Use [view_uplot()] to read and display a window from a
#' `StudyCache` directly.
#'
#' @param panels List of panels, one per channel. Each is a list holding
#'   numeric `x` and `y` of equal length, and optionally a `label` and a
#'   `color`. Lengths may differ between panels.
#' @param window Loaded range as `list(min =, max =)` in x units. Panels are
#'   drawn against this rather than against their own extents, so overview
#'   panels whose extrema fall on different samples still line up. Defaults to
#'   the union of the panel x extents.
#' @param extent Record range as `list(min =, max =)` in x units. Panning is
#'   clamped to this, so a reader may pan beyond what is loaded and have the
#'   controller fill it in. Defaults to `window`.
#' @param backend Renderer to draw with, resolved in the browser. Only
#'   `"uplot"` ships today.
#' @param scale X-scale description. `kind` may be `"index"` for sample
#'   numbers, `"elapsed"` for elapsed seconds, or `"timestamp"` for Unix
#'   timestamps.
#' @param panel_height Height of each channel panel in CSS pixels.
#' @param width,height Optional widget dimensions.
#' @param elementId Optional HTML element id.
#' @return An `htmlwidget`.
#' @seealso [view_uplot()], [read_viewport()]
#' @export
gram_plot <- function(
  panels,
  window = NULL,
  extent = NULL,
  backend = "uplot",
  scale = list(kind = "index", rate = 1),
  panel_height = 120,
  width = NULL,
  height = NULL,
  elementId = NULL
) {
  panels <- gm_validate_panels(panels)
  if (is.null(window)) {
    bounds <- range(unlist(lapply(panels, function(panel) range(panel$x))))
    window <- list(min = bounds[[1L]], max = bounds[[2L]])
  }
  window <- gm_validate_range(window, "window")
  extent <- gm_validate_range(extent %||% window, "extent")

  if (length(backend) != 1L || !is.character(backend) || !nzchar(backend)) {
    stop("`backend` must be a single non-empty string", call. = FALSE)
  }

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

  if (length(panel_height) != 1L || !is.finite(panel_height) || panel_height < 80) {
    stop("`panel_height` must be a single number of at least 80", call. = FALSE)
  }

  # payload -> renderValue(x) in gram_plot.js
  x <- list(
    backend = backend,
    panels = panels,
    window = window,
    extent = extent,
    scale = scale,
    layout = list(
      panel_height = as.double(panel_height)
    )
  )

  htmlwidgets::createWidget(
    name = "gram_plot",
    x,
    width = width,
    height = height,
    package = "gram",
    elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(
      browser.fill = TRUE, # fill viewer/browser
      viewer.fill = TRUE
    )
  )
}

# Returns the panels with `x` and `y` as doubles wrapped in I(), because a
# constant channel really does reduce to a single point at a coarse tier and an
# unwrapped length-1 vector would reach the browser as a scalar rather than an
# array.
gm_validate_panels <- function(panels) {
  if (!is.list(panels) || length(panels) == 0L) {
    stop("`panels` must be a list holding at least one panel", call. = FALSE)
  }

  lapply(seq_along(panels), function(i) {
    panel <- panels[[i]]
    where <- paste0("panel ", i)
    if (!is.list(panel) || is.null(panel$x) || is.null(panel$y)) {
      stop("every panel must hold `x` and `y`; ", where, " does not", call. = FALSE)
    }
    if (!is.numeric(panel$x) || !is.numeric(panel$y)) {
      stop("`x` and `y` must be numeric; ", where, " is not", call. = FALSE)
    }
    if (length(panel$x) != length(panel$y)) {
      stop(
        "`x` and `y` must have equal length within a panel; ", where,
        " holds ", length(panel$x), " and ", length(panel$y),
        call. = FALSE
      )
    }
    if (length(panel$x) == 0L) {
      stop("a panel cannot be empty; ", where, " is", call. = FALSE)
    }
    if (any(!is.finite(panel$x)) || is.unsorted(panel$x, strictly = FALSE)) {
      stop(
        "`x` must hold finite values in increasing order; ", where,
        " does not",
        call. = FALSE
      )
    }
    if (any(is.infinite(panel$y))) {
      stop("`y` cannot hold infinite values; ", where, " does", call. = FALSE)
    }

    # a missing colour is left out rather than sent as null, which jsonlite
    # would render as an empty object; the adapter falls back on
    # `panel.color || <default>`
    keep <- list()
    if (!is.null(panel$label)) {
      keep$label <- as.character(panel$label)[[1L]]
    }
    if (!is.null(panel$color)) {
      keep$color <- as.character(panel$color)[[1L]]
    }
    keep$x <- I(as.double(panel$x))
    keep$y <- I(as.double(panel$y))
    keep
  })
}

gm_validate_range <- function(range, arg) {
  if (!is.list(range) || !all(c("min", "max") %in% names(range))) {
    stop("`", arg, "` must be a list holding `min` and `max`", call. = FALSE)
  }
  bounds <- c(as.double(range$min), as.double(range$max))
  if (length(bounds) != 2L || any(!is.finite(bounds)) || bounds[[2L]] <= bounds[[1L]]) {
    stop("`", arg, "` must hold two finite bounds with min < max", call. = FALSE)
  }
  list(min = bounds[[1L]], max = bounds[[2L]])
}


# --- shiny bindings (boilerplate, required by htmlwidgets) ------

#' Shiny output binding for a gram plot
#'
#' @param outputId Output variable to read from.
#' @param width,height Valid CSS dimensions.
#' @return A Shiny widget output element.
#' @export
gram_plotOutput <- function(outputId, width = "100%",
                           height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "gram_plot", width, height, package = "gram"
  )
}

#' Shiny render function for a gram plot
#'
#' @param expr Expression that produces a [gram_plot()] widget.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is quoted.
#' @return A Shiny render function.
#' @export
render_gram_plot <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(
    expr,
    gram_plotOutput,
    env,
    quoted = TRUE
  )
}
