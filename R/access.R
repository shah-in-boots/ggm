# Remaining data-access surface (blueprint S3.4). STUBS.
#
# These round out the read API alongside `get_window()`. They are stubbed so
# the intended surface is visible and callable, but they fail loudly with their
# milestone rather than pretending to work.

#' Whole-study overview (not yet implemented)
#'
#' Planned for milestone **M2.5**. Returns the zoomed-out navigation map: a
#' faint downsampled signal tier (from the signal pyramid) plus the sharp event
#' layer (aggregated annotation spans/ticks/flags) you scroll by.
#'
#' @param study A `ggm_study` from [open_study()].
#' @param channels Channel labels to include, or `NULL` for all.
#' @param filter Optional annotation filter expression for the event layer.
#'
#' @return (Planned) overview data for the two-layer map. Currently errors.
#' @export
get_overview <- function(study, channels = NULL, filter = NULL) {
  not_yet_implemented("get_overview()", "M2.5")
}

#' Query annotations over a window (not yet implemented)
#'
#' Planned for milestone **M3**. Returns a filtered view of the study's
#' annotations, keyed on `sample` + `channel`, for drawing and "jump to next
#' event" navigation.
#'
#' @param study A `ggm_study` from [open_study()].
#' @param range Optional sample or time range to restrict to.
#' @param filter Optional filter expression (e.g. `type == "AVB"`).
#'
#' @return (Planned) an annotation table. Currently errors.
#' @export
get_annotations <- function(study, range = NULL, filter = NULL) {
  not_yet_implemented("get_annotations()", "M3")
}
