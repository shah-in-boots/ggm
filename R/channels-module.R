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
    # both controls report character values; NULL means nothing selected, which
    # is flattened here so it cannot read as "not ready" upstream
    shiny::reactive({
      sort(as.integer(input$channels %||% integer()))
    })
  })
}


# internals -------------------------------------------------------------

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
