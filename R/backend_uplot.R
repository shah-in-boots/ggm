# backend_uplot.R -- uPlot implementation of the plotting contract
#
# only file (plus its JS adapter) that knows uPlot exists.
# swapping backends = new backend_*.R + ggm-adapter-*.js,
# zero changes to backend.R or shiny modules.

# create a ggm plot widget
#
# columns: columnar list(x, ch1, ch2, ...) in domain units
# scale:   list(kind = "index", rate = 30000) or
#          list(kind = "time", unit = "s")
# series:  optional list of per-channel lists(label, color)
# backend: adapter name registered in GGM.adapters (JS side)
ggm_plot <- function(columns,
                     scale  = list(kind = "index", rate = 1),
                     series = NULL,
                     width  = NULL, height = NULL,
                     elementId = NULL) {

  # default series config: one entry per non-x column
  n_ch <- length(columns) - 1L
  if (is.null(series)) {
    series <- lapply(seq_len(n_ch), function(i) {
      list(label = paste0("ch", i))
    })
  }

  # payload -> renderValue(x) in ggm_plot.js
  # I() keeps length-1 vectors as JSON arrays
  x <- list(
    backend = "uplot",
    columns = lapply(columns, I),
    scale   = scale,
    series  = series
  )

  htmlwidgets::createWidget(
    name = "ggm_plot",
    x,
    width = width, height = height,
    package = "ggm",
    elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(
      browser.fill = TRUE,   # fill viewer/browser
      viewer.fill  = TRUE
    )
  )
}

# --- shiny bindings (boilerplate, required by htmlwidgets) ------

ggm_plotOutput <- function(outputId, width = "100%",
                           height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "ggm_plot", width, height, package = "ggm"
  )
}

renderGgm_plot <- function(expr, env = parent.frame(),
                           quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  htmlwidgets::shinyRenderWidget(
    expr, ggm_plotOutput, env, quoted = TRUE
  )
}
