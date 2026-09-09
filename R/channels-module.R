#' Choose which channels are on screen
#'
#' A Shiny module that lists the channels a record carries and reports which
#' are selected. The server half returns a reactive and touches no plot.
#'
#' @param id Module id, matched between the UI and server halves.
#' @param channels A `StudyCache`, whose WFDB header names the channels, or a
#'   character vector of channel labels.
#' @param variant Shape of the control. `"checkbox"` gives a column, one row
#'   per channel; `"dropdown"` gives a multi-select.
#' @param selected Channels selected at startup, as labels or as 1-based
#'   indices. Defaults to all of them.
#' @param label Control label. `NULL` draws none.
#'
#' @return `gram_channelsUI()` returns a Shiny input control.
#'   `gram_channelsServer()` returns a reactive giving the selected channel
#'   indices: 1-based into `channels`, ascending, and `integer(0)` when
#'   nothing is selected. Labels are `channels[chosen()]`.
#'
#' @name gram_channels
#' @family controller
#' @keywords internal
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

  labels <- gm_get_labels(channels)
  values <- seq_along(labels)
  chosen <- sort(unique(gm_match_channels(selected, labels, arg = "selected")))
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
    # both controls report character values; NULL means nothing selected, which
    # is flattened here so it cannot read as "not ready" upstream
    shiny::reactive({
      sort(as.integer(input$channels %||% integer()))
    })
  })
}


# internals -------------------------------------------------------------

gm_get_labels <- function(channels) {
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
