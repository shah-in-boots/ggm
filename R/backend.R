# proxy -----------------------------------------------------------------

gm_proxy <- function(id, session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) stop("gm_proxy requires a shiny session")
  structure(
    list(id = session$ns(id), session = session),
    class = "gm_proxy"
  )
}

gm_send <- function(proxy, channel, payload) {
  stopifnot(inherits(proxy, "gm_proxy"))
  proxy$session$sendCustomMessage(
    channel,
    c(list(id = proxy$id), payload)
  )
  invisible(proxy)
}


# verbs -----------------------------------------------------------------

gm_set_visible <- function(proxy, channels) {
  if (!is.numeric(channels) || any(!is.finite(channels)) || any(channels < 1)) {
    stop("`channels` must be 1-based channel indices", call. = FALSE)
  }
  gm_send(
    proxy,
    "gram:set_visible",
    list(channels = I(as.integer(sort(unique(channels)))))
  )
}


# selection -------------------------------------------------------------

#' Canonicalise a viewer selection to a sample range
#'
#' @param cache A `StudyCache`.
#' @param selection The widget's selection input: a list holding `xmin` and
#'   `xmax` in elapsed seconds. `NULL` before anything has been selected.
#' @return A list with `begin` and `end` sample indices delimiting a half-open
#'   range, clamped to the record. `NULL` when nothing is selected and when the
#'   selection holds no samples.
#' @family backend viewers
#' @export
normalize_selection <- function(cache, selection) {
  if (is.null(selection)) {
    return(NULL)
  }
  if (!is.list(selection) || !all(c("xmin", "xmax") %in% names(selection))) {
    stop("`selection` must be a list holding `xmin` and `xmax`", call. = FALSE)
  }

  seconds <- c(as.double(selection$xmin), as.double(selection$xmax))
  if (length(seconds) != 2L || any(!is.finite(seconds))) {
    stop("`selection` must hold two finite seconds", call. = FALSE)
  }

  # a right-to-left drag reports its ends in the order they were drawn
  samples <- gm_study_seconds_to_sample(sort(seconds), cache@sample_rate)
  samples <- pmin(pmax(samples, 0), cache@n_samples)

  if (samples[[2L]] <= samples[[1L]]) {
    return(NULL)
  }
  list(begin = samples[[1L]], end = samples[[2L]])
}
