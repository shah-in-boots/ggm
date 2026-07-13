# dev/test_backend.R -- smoke tests for the plotting backend
# run interactively, not part of package

# --- tier 1: standalone, no shiny -------------------------------
# devtools::load_all(); then run this block.
# expected: 2-channel plot in the viewer, drag-zoom on x works

test_standalone <- function(n = 5000) {
  x  <- seq_len(n)                       # sample-number domain
  y1 <- sin(x / 50) + rnorm(n, sd = .1)
  y2 <- cos(x / 80) + rnorm(n, sd = .1)

  ggm_plot(
    columns = list(x, y1, y2),
    scale   = list(kind = "index", rate = 1000),
    series  = list(
      list(label = "ch1", color = "steelblue"),
      list(label = "ch2", color = "firebrick")
    )
  )
}

# --- tier 2: minimal shiny harness ------------------------------
# tests all three proxy verbs against a live widget.
# expected: buttons push data / zoom / toggle without re-render
# (watch for flicker -- there should be none)

test_shiny <- function() {
  ui <- shiny::fluidPage(
    ggm_plotOutput("p", height = "350px"),
    shiny::actionButton("new_data", "new data"),
    shiny::actionButton("zoom",     "zoom 1000:2000"),
    shiny::actionButton("toggle",   "toggle ch2")
  )

  server <- function(input, output, session) {
    n <- 5000
    output$p <- renderGgm_plot(test_standalone(n))

    shiny::observeEvent(input$new_data, {
      x <- seq_len(n)
      ggm_set_data(ggm_proxy("p"), list(
        x,
        sin(x / 30) + rnorm(n, sd = .1),
        cos(x / 60) + rnorm(n, sd = .1)
      ))
    })

    shiny::observeEvent(input$zoom, {
      ggm_set_viewport(ggm_proxy("p"), 1000, 2000)
    })

    shiny::observeEvent(input$toggle, {
      ggm_set_series(ggm_proxy("p"), 2,
                     visible = input$toggle %% 2 == 0)
    })
  }

  shiny::shinyApp(ui, server)
}

# usage:
#   devtools::load_all()
#   test_standalone()      # tier 1
#   test_shiny()           # tier 2
