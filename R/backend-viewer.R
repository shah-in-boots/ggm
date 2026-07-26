#' View a study window with the uPlot backend
#'
#' `view_uplot()` is a backend-specific development viewer. It reads a fixed
#' interval from the canonical WFDB signal, adapts the result to uPlot's aligned
#' column format, and returns the standalone uPlot widget. It is useful for
#' exercising and testing the uPlot backend without a Shiny controller.
#'
#' The widget contains only the requested `begin` to `end` or `interval` range.
#' When neither `end` nor `interval` is supplied, the viewer reads ten seconds
#' from `begin`. Drag horizontally to zoom into that loaded range, scroll
#' horizontally (or use Shift+wheel) to pan, and double-click to reset the
#' range. A future interactive study controller can manage dynamic viewport
#' reads while reusing the same uPlot backend.
#'
#' @param cache A `StudyCache` created by [study_cache()].
#' @inheritParams read_study_signal
#' @param channels Channel labels or indices. Defaults to all channels.
#' @param units Signal units passed to [read_study_signal()].
#' @param width,height Optional widget dimensions.
#' @return An `htmlwidget`.
#' @family backend viewers
#' @export
view_uplot <- function(cache,
                       begin = NULL,
                       end = NULL,
                       interval = NULL,
                       channels = NULL,
                       units = c("physical", "digital"),
                       width = NULL,
                       height = 500) {
  if (missing(end) && missing(interval)) {
    interval <- 10
  }
  units <- match.arg(units)
  signal <- as.data.frame(read_study_signal(
    cache = cache,
    begin = begin,
    end = end,
    interval = interval,
    channels = channels,
    units = units
  ))

  channelNames <- setdiff(names(signal), "sample")
  if (length(channelNames) == 0L) {
    stop("the study window did not contain any signal channels", call. = FALSE)
  }

  columns <- c(
    list(signal$sample / cache@sample_rate),
    unname(signal[channelNames])
  )
  series <- lapply(channelNames, function(channel) list(label = channel))

  ggm_plot(
    columns = columns,
    scale = list(kind = "elapsed", unit = "s"),
    series = series,
    width = width,
    height = height
  )
}
