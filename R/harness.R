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
#' Dragging across the viewer reports the selected sample range above the
#' script state, through [normalize_selection()]. Nothing consumes that range
#' yet -- the readout exists to confirm the browser can reach R at all.
#'
#' @param cache A `StudyCache` from [study_cache()].
#' @param begin,interval Window shown in the viewer panel.
#' @param channels Channels loaded into the viewer panel. Defaults to every
#'   channel in the header. The [gram_channels] module beside the viewer
#'   switches these on and off; because the widget already holds them all,
#'   that costs no further read of the record.
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

  viewChannels <- channels %||% cache@channels
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
    viewer = gram_plotOutput("viewer", height = "420px"),
    channels = gram_channelsUI("channels", viewChannels),
    tracing = gram_tracingOutput("tracing", height = "340px"),
    script = shiny::textAreaInput("script", NULL, value = script),
    run = shiny::actionButton("run", "Run script"),
    status = shiny::uiOutput("status")
  )

  server <- function(input, output, session) {
    current <- shiny::reactiveVal(NULL)
    failure <- shiny::reactiveVal(NULL)

    # the viewer reports a completed drag; nothing consumes the range yet
    selected <- shiny::reactive(
      normalize_selection(cache, input$viewer_selection)
    )

    # channel visibility is view state the controller owns. The module reports
    # what was chosen and this is the one line that connects it to the viewer;
    # the widget already holds every channel, so it never re-reads the record.
    chosen <- gram_channelsServer("channels")
    shiny::observe({
      gm_set_visible(gm_proxy("viewer"), chosen())
    })

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
      window <- selected()
      report <- if (is.null(window)) {
        "selection: drag across the signal"
      } else {
        paste0(
          "selection: samples ", window$begin, "-", window$end, "  (",
          format((window$end - window$begin) / cache@sample_rate, digits = 4),
          " s)"
        )
      }

      if (!is.null(failure())) {
        return(shiny::tags$pre(
          class = "gram-failed",
          paste(report, failure(), sep = "\n\n")
        ))
      }
      tracing <- current()
      shiny::req(tracing)
      shiny::tags$pre(paste(
        c(report, "", utils::capture.output(print(tracing))),
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
