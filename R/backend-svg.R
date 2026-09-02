#' Render a tracing as an animated SVG widget
#'
#' Compiles the tracing with [tracing_spec()] and hands the markup and the
#' timeline to the browser.
#'
#' @param x A `Tracing`.
#' @param autoplay Whether the timeline runs on load.
#' @param controls Whether play, pause, and restart buttons are shown.
#' @param width,height Optional widget dimensions.
#' @param elementId Optional HTML element id.
#' @return An `htmlwidget`.
#' @family tracing
#' @export
gram_tracing <- function(x,
                        autoplay = TRUE,
                        controls = TRUE,
                        width = NULL,
                        height = NULL,
                        elementId = NULL) {
  spec <- tracing_spec(x)

  htmlwidgets::createWidget(
    name = "gram_tracing",
    list(
      spec = spec,
      autoplay = isTRUE(autoplay),
      controls = isTRUE(controls)
    ),
    width = width,
    height = height,
    package = "gram",
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
gram_tracingOutput <- function(outputId, width = "100%", height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "gram_tracing", width, height, package = "gram"
  )
}

#' Shiny render function for a tracing
#'
#' @param expr Expression that produces a [gram_tracing()] widget.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is quoted.
#' @return A Shiny render function.
#' @export
render_gram_tracing <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(
    expr,
    gram_tracingOutput,
    env,
    quoted = TRUE
  )
}
