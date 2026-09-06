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
#' Opens a page with three panels: the signal viewer, a scripting panel for the
#' tracing grammar, and the compiled tracing. Scripts are evaluated by
#' [eval_tracing()], not by R.
#'
#' The viewer opens on the whole record. At a coarse overview tier that is the
#' study navigator, so a reader starts by seeing the study rather than an
#' opening slice of it. Dragging across a panel zooms; the wheel pans; both
#' report the range wanted and are answered with whichever tier fits it. The
#' harness is the controller: it knows the backend by name only, and every
#' change it makes -- a new window, a new tier, a different set of channels --
#' is one push of a fresh spec into the live widget.
#'
#' @param cache A `StudyCache` from [study_cache()].
#' @param window Sample range the viewer opens on, as `list(begin =, end =)`.
#'   Defaults to the whole record.
#' @param channels Channels loaded into the viewer panel. Defaults to every
#'   channel in the header.
#' @param backend Renderer for the viewer panel; see [gram_plot()].
#' @param script Initial contents of the scripting panel.
#' @param ... Passed to [shiny::shinyApp()].
#' @return A Shiny app object.
#' @family harness
#' @export
gram_harness <- function(cache,
                        window = NULL,
                        channels = NULL,
                        backend = c("uplot"),
                        script = harnessScript,
                        ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("gram_harness() needs the shiny package", call. = FALSE)
  }
  backend <- match.arg(backend)

  viewChannels <- channels %||% cache@channels
  startWindow <- window %||% list(begin = 0, end = cache@n_samples)
  elapsed <- list(kind = "elapsed", unit = "s")
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
      format(cache@sample_rate), " Hz  ",
      backend
    ),
    viewer = gram_plotOutput("viewer", height = "420px"),
    reset = shiny::actionButton("reset", "Whole study"),
    channels = gram_channelsUI("channels", viewChannels),
    tracing = gram_tracingOutput("tracing", height = "340px"),
    script = shiny::textAreaInput("script", NULL, value = script),
    run = shiny::actionButton("run", "Run script"),
    status = shiny::uiOutput("status")
  )

  server <- function(input, output, session) {
    current <- shiny::reactiveVal(NULL)
    failure <- shiny::reactiveVal(NULL)
    window <- shiny::reactiveVal(startWindow)

    # The browser is the only party that knows how wide a panel is, and the
    # tier depends on it. 1200 stands in until the widget reports.
    view <- shiny::reactive({
      gm_viewport_panels(
        cache,
        window = window(),
        channels = viewChannels,
        width_px = input$viewer_width %||% 1200
      )
    })

    chosen <- gram_channelsServer("channels")

    # What is on screen: the loaded panels, narrowed to the picked channels.
    # Nothing picked means nothing to push, and the last state stands.
    shown <- shiny::reactive({
      shiny::req(length(chosen()) > 0L)
      view()$panels[chosen()]
    })

    # Rendered once, with every channel, from nothing reactive. Every later
    # change -- a new window, a new tier, a width report, a channel toggle --
    # invalidates shown() and is one push into the live widget, so the stack is
    # never torn down and rebuilt through Shiny. The first push repeats the
    # opening picture; that is the price of never rendering against an
    # `input$channels` that has not arrived yet.
    output$viewer <- render_gram_plot({
      opening <- shiny::isolate(view())
      gram_plot(
        panels = opening$panels,
        window = opening$window,
        extent = opening$extent,
        backend = backend,
        scale = elapsed,
        height = 420
      )
    })

    shiny::observeEvent(shown(), {
      gm_set_data(
        gm_proxy("viewer"),
        panels = shown(),
        window = view()$window,
        backend = backend,
        scale = elapsed
      )
    })

    # zoom and pan arrive on the same channel: both say which range is wanted
    shiny::observeEvent(input$viewer_viewport, {
      requested <- normalize_selection(cache, input$viewer_viewport)
      if (!is.null(requested)) {
        window(requested)
      }
    })

    shiny::observeEvent(input$reset, {
      window(list(begin = 0, end = cache@n_samples))
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

    shiny::isolate(run_script(script))

    shiny::observeEvent(input$run, {
      run_script(input$script)
    })

    output$status <- shiny::renderUI({
      shown <- window()
      # naming the tier is not decoration: an overview tier is an envelope of
      # bucket extrema, and nothing may be measured or annotated on it
      tier <- if (identical(view()$resolution, "raw")) {
        "raw"
      } else {
        paste0("overview ", view()$resolution, " (level ", view()$level, ")")
      }
      report <- paste0(
        "window: samples ", shown$begin, "-", shown$end, "  (",
        format((shown$end - shown$begin) / cache@sample_rate, digits = 4),
        " s)  ", tier
      )

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
