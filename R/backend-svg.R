# backend-svg.R -------------------------------------------------------
# The presentation renderer: an SVG widget driven by anime.js.
#
# Separate from the uPlot backend on purpose. Exploration optimises for
# latency over a long record; presentation optimises for precision over a
# short window, and the two renderers share only the samples and the
# annotations underneath them.

#' Render a tracing as an animated SVG widget
#'
#' Compiles the tracing with [tracing_spec()] and hands the markup and the
#' timeline to the browser. The animation's last frame is the composition
#' at rest, so the same widget paused at the end is the print still.
#'
#' @param x A `Tracing`.
#' @param autoplay Whether the timeline runs on load.
#' @param controls Whether play, pause, and restart buttons are shown.
#' @param width,height Optional widget dimensions.
#' @param elementId Optional HTML element id.
#' @return An `htmlwidget`.
#' @family tracing
#' @export
ggm_tracing <- function(x,
                        autoplay = TRUE,
                        controls = TRUE,
                        width = NULL,
                        height = NULL,
                        elementId = NULL) {
  spec <- tracing_spec(x)

  htmlwidgets::createWidget(
    name = "ggm_tracing",
    list(
      spec = spec,
      autoplay = isTRUE(autoplay),
      controls = isTRUE(controls)
    ),
    width = width,
    height = height,
    package = "ggm",
    elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(
      browser.fill = TRUE,
      viewer.fill = TRUE
    )
  )
}

#' Shiny output binding for a tracing
#'
#' @param outputId Output variable to read from.
#' @param width,height Valid CSS dimensions.
#' @return A Shiny widget output element.
#' @export
ggm_tracingOutput <- function(outputId, width = "100%", height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "ggm_tracing", width, height, package = "ggm"
  )
}

#' Shiny render function for a tracing
#'
#' @param expr Expression that produces a [ggm_tracing()] widget.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is quoted.
#' @return A Shiny render function.
#' @export
render_ggm_tracing <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(
    expr,
    ggm_tracingOutput,
    env,
    quoted = TRUE
  )
}
