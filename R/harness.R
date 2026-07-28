# harness.R -----------------------------------------------------------
# A development harness: the uPlot viewer, a scripting panel, and the
# tracing the script builds, in one page.
#
# Deliberately thin. The chrome is inst/harness/index.html and nothing in
# here reads it, so the skin can be rewritten without touching R. The
# script panel evaluates the tracing grammar through eval_tracing(), which
# is sealed -- it is not an R console.

harnessScript <- 'tracing(
  begin = "00:00:00",
  interval = "1200 ms",
  channels = c("HIS D", "CS 1-2", "RV 1-2")
) |>
  reveal() |>
  add_arrow(
    from = at(300, "RV 1-2"),
    to = at(420, "HIS D"),
    label = "VA"
  ) |>
  emphasize(at(420, "HIS D"), label = "retrograde A")'


#' Launch the development harness
#'
#' Opens a page with three panels: the uPlot viewer over a fixed window,
#' a scripting panel for the tracing grammar, and the compiled tracing
#' with playback controls. The script panel runs on load, so the harness
#' opens with a working tracing rather than an empty stage.
#'
#' The panel accepts the tracing grammar only. Scripts are checked against
#' the verb whitelist and evaluated in the sealed environment built by
#' [gram_verbs()], so a script cannot reach R outside the grammar.
#'
#' @param cache A `StudyCache` from [study_cache()].
#' @param begin,interval Window shown in the viewer panel.
#' @param channels Channels shown in the viewer panel. Defaults to the
#'   first six in the header.
#' @param script Initial contents of the scripting panel.
#' @param ... Passed to [shiny::shinyApp()].
#' @return A Shiny app object.
#' @family harness
#' @export
gram_harness <- function(cache,
                        begin = "00:00:00",
                        interval = "1200 ms",
                        channels = NULL,
                        script = harnessScript,
                        ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("gram_harness() needs the shiny package", call. = FALSE)
  }

  viewChannels <- channels %||% utils::head(cache@channels, 6L)
  template <- system.file("harness", "index.html", package = "gram")
  if (!nzchar(template)) {
    stop("harness template not found; is gram installed correctly?", call. = FALSE)
  }

  ui <- shiny::htmlTemplate(
    template,
    record = paste0(
      cache@stem, "  ",
      format(cache@n_samples / cache@sample_rate, digits = 4), " s  ",
      length(cache@channels), " ch  ",
      format(cache@sample_rate), " Hz"
    ),
    viewer = gram_plotOutput("viewer", height = "260px"),
    tracing = gram_tracingOutput("tracing", height = "340px"),
    script = shiny::textAreaInput("script", NULL, value = script),
    run = shiny::actionButton("run", "Run script"),
    status = shiny::uiOutput("status")
  )

  server <- function(input, output, session) {
    current <- shiny::reactiveVal(NULL)
    failure <- shiny::reactiveVal(NULL)

    output$viewer <- render_gram_plot({
      view_uplot(
        cache,
        begin = begin,
        interval = interval,
        channels = viewChannels
      )
    })

    run_script <- function(text) {
      result <- tryCatch(
        eval_tracing(text, cache),
        error = function(e) e
      )
      if (inherits(result, "error")) {
        failure(conditionMessage(result))
      } else {
        failure(NULL)
        current(result)
      }
    }

    # run once on load so the harness opens with something on the stage
    shiny::isolate(run_script(script))

    shiny::observeEvent(input$run, {
      run_script(input$script)
    })

    output$status <- shiny::renderUI({
      if (!is.null(failure())) {
        return(shiny::tags$pre(class = "gram-failed", failure()))
      }
      tracing <- current()
      shiny::req(tracing)
      shiny::tags$pre(paste(
        utils::capture.output(print(tracing)),
        collapse = "\n"
      ))
    })

    output$tracing <- render_gram_tracing({
      tracing <- current()
      shiny::req(tracing)
      gram_tracing(tracing)
    })
  }

  shiny::shinyApp(ui, server, ...)
}
