# channels-module.R ----------------------------------------------------
# A Shiny module for choosing which channels are on screen.
#
# It knows nothing about plots. The server half returns a reactive of the
# selected channel indices and stops there, so wiring it to a viewer is one
# line at the call site and the same module can drive a gram plot, a table, or
# anything else that takes a channel set.
#
# The control's shape is a UI argument because it is purely presentational: a
# checkbox column and a dropdown choose the same thing. Adding a third shape
# means one more branch in the switch below and nothing else.
#
# Channels come from the record's WFDB header, so a StudyCache can be handed
# in directly rather than the caller reaching for @channels.

#' Choose which channels are on screen
#'
#' A Shiny module that lists the channels a record carries and reports which
#' are selected. It is a plain add-on: the server half returns a reactive and
#' does not touch any plot, so one line at the call site connects it to
#' whatever should respond.
#'
#' @details
#' The module reports a selection and stops there; one line connects it to
#' whatever should respond. [gram_harness()] wires it to a [gram_plot()]
#' viewer through the plotting verbs:
#'
#' ```r
#' # ui
#' gram_channelsUI("channels", cache)
#'
#' # server
#' chosen <- gram_channelsServer("channels")
#' shiny::observe({
#'   gm_set_visible(gm_proxy("viewer"), chosen())
#' })
#' ```
#'
#' Because the widget already holds every channel it was built with, that
#' costs no further read of the record -- it only moves lanes on and off
#' screen. Those two verbs are package-internal for now, so outside \pkg{gram}
#' drive your own output from `chosen()` instead.
#'
#' The list is fixed when the UI is built. Pass the channels the viewer
#' actually loaded, which is what can be switched back on -- for a study
#' opened whole, that is every channel in the header.
#'
#' @param id Module id, matched between the UI and server halves.
#' @param channels A `StudyCache`, whose WFDB header names the channels, or a
#'   character vector of channel labels.
#' @param variant Shape of the control. `"checkbox"` gives a column, one row
#'   per channel; `"dropdown"` gives a multi-select. Both choose the same
#'   thing, so this is a display decision only.
#' @param selected Channels selected at startup, as labels or as 1-based
#'   indices. Defaults to all of them.
#' @param label Control label. `NULL` draws none, which suits a control that
#'   already sits under a heading.
#'
#' @return `gram_channelsUI()` returns a Shiny input control.
#'   `gram_channelsServer()` returns a reactive giving the selected channel
#'   indices: 1-based into `channels`, ascending, and `integer(0)` when
#'   nothing is selected. Labels are `channels[chosen()]`.
#'
#' @name gram_channels
#' @family shiny modules
NULL

#' @rdname gram_channels
#' @export
gram_channelsUI <- function(id,
                            channels,
                            variant = c("checkbox", "dropdown"),
                            selected = NULL,
                            label = NULL) {
  variant <- match.arg(variant)
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("gram_channelsUI() needs the shiny package", call. = FALSE)
  }

  labels <- gm_channel_labels(channels)
  values <- seq_along(labels)
  chosen <- gm_channel_selection(selected, labels)
  ns <- shiny::NS(id)

  switch(
    variant,
    checkbox = shiny::checkboxGroupInput(
      ns("channels"),
      label,
      choiceNames = as.list(labels),
      choiceValues = as.list(values),
      selected = chosen
    ),
    dropdown = shiny::selectInput(
      ns("channels"),
      label,
      choices = stats::setNames(values, labels),
      selected = chosen,
      multiple = TRUE
    )
  )
}

#' @rdname gram_channels
#' @export
gram_channelsServer <- function(id) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("gram_channelsServer() needs the shiny package", call. = FALSE)
  }

  shiny::moduleServer(id, function(input, output, session) {
    # both controls report their values as character; nothing selected comes
    # back NULL, which has to stay distinguishable from "not ready" upstream,
    # so it is flattened to an empty selection rather than passed on
    shiny::reactive({
      sort(as.integer(input$channels %||% integer()))
    })
  })
}


# internals -------------------------------------------------------------

# channels may be a StudyCache, read from its WFDB header, or a plain
# character vector so the module is usable without one
gm_channel_labels <- function(channels) {
  if (S7::S7_inherits(channels, StudyCache)) {
    channels <- channels@channels
  }
  if (!is.character(channels) || length(channels) == 0L) {
    stop(
      "`channels` must be a StudyCache or a non-empty character vector",
      call. = FALSE
    )
  }
  channels
}

# accept the startup selection as labels or as indices, and refuse anything
# that does not land on a channel rather than silently dropping it
gm_channel_selection <- function(selected, labels) {
  if (is.null(selected)) {
    return(seq_along(labels))
  }

  if (is.character(selected)) {
    at <- match(selected, labels)
    if (anyNA(at)) {
      stop(
        "`selected` names channels this record does not carry: ",
        paste(selected[is.na(at)], collapse = ", "),
        call. = FALSE
      )
    }
    return(sort(at))
  }

  if (!is.numeric(selected) || any(!is.finite(selected))) {
    stop("`selected` must be channel labels or 1-based indices", call. = FALSE)
  }
  selected <- as.integer(selected)
  if (any(selected < 1L) || any(selected > length(labels))) {
    stop(
      "`selected` is outside the ", length(labels),
      " channels this record carries",
      call. = FALSE
    )
  }
  sort(unique(selected))
}
