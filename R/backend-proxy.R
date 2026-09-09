# The controller's side of a live widget: a handle to it, the way to message
# it, and the verbs a controller uses in both directions -- push a fresh spec
# down, and turn the selection the widget reports back up into samples.
#
# Only gm_proxy() and gm_send() know the transport is Shiny (a session, a
# custom message). Everything above them -- which backend, what spec, what
# window -- is settled before the message exists. A host other than Shiny
# replaces those two functions; the verbs above them do not change. The
# harness and the channels module are Shiny through and through and would be
# replaced with it -- they are the host, not the seam.

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

# Replace what an already-rendered viewer is drawing, rather than re-rendering
# the widget. The spec is built here, by the same backend that built the
# widget's, so a push and a first render are the same translation; the window
# travels beside it because it is what the panels are drawn against. The
# record extent does not travel, since it cannot change while the widget
# lives. Which channels are on screen is decided by which panels are handed
# over: narrowing them is how a controller hides a channel.
gm_set_data <- function(proxy,
                        panels,
                        window,
                        backend = c("uplot", "plotly"),
                        scale = list(kind = "index", rate = 1),
                        panel_height = 120) {
  panels <- gm_validate_panels(panels)
  window <- gm_validate_range(window, "window")
  chosen <- gm_get_backend(match.arg(backend))
  gm_send(
    proxy,
    "gram:set_data",
    list(
      spec = chosen$spec(panels, window, scale, panel_height),
      window = window
    )
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
#' @family controller
#' @keywords internal
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
  samples <- gm_seconds_to_samples(sort(seconds), cache@sample_rate)
  samples <- pmin(pmax(samples, 0), cache@n_samples)

  if (samples[[2L]] <= samples[[1L]]) {
    return(NULL)
  }
  list(begin = samples[[1L]], end = samples[[2L]])
}
