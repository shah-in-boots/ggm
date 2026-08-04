# backend.R -- plotting contract, backend-neutral
#
# all gram code talks to plots through these verbs only.
# each verb sends a "gram:*" custom message; gram-dispatch.js
# routes it to whichever adapter owns the instance.
#
# verbs: set_data, set_viewport, set_series, set_visible
# (annotations verb added later, same pattern)
#
# the browser reports back on one input, <outputId>_selection; see
# normalize_selection() below.
#
# units: viewport always in domain units (time or sample idx),
# never pixels. backend converts internally.

# --- proxy ------------------------------------------------------

# handle to a live widget in a running shiny session.
# no-op outside shiny (standalone tier-1 tests use renderValue only)
#
# id: outputId of the widget
gm_proxy <- function(id, session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) stop("gm_proxy requires a shiny session")
  structure(
    list(id = session$ns(id), session = session),
    class = "gm_proxy"
  )
}

# internal: send one message on a gram channel
# payload must be a named list; id injected here
gm_send <- function(proxy, channel, payload) {
  stopifnot(inherits(proxy, "gm_proxy"))
  proxy$session$sendCustomMessage(
    channel,
    c(list(id = proxy$id), payload)
  )
  invisible(proxy)
}

# --- verbs ------------------------------------------------------

# replace plot data, no widget re-render
# columns: list(x, ch1, ch2, ...) -- columnar, uPlot/Arrow shaped.
# vectors must stay arrays in JSON even at length 1, so wrap with I()
gm_set_data <- function(proxy, columns) {
  gm_send(proxy, "gram:set_data", list(columns = lapply(columns, I)))
}

# set visible x (and optionally y) range in domain units
gm_set_viewport <- function(proxy, xmin, xmax, ymin = NULL, ymax = NULL) {
  gm_send(
    proxy,
    "gram:set_viewport",
    list(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)
  )
}

# put a set of channels on screen, by 1-based channel index.
#
# which channels are shown is view state, so the controller owns it and the
# backend renders what it is told. the widget already holds every channel's
# data, so this costs no read -- do not re-render the widget to hide a lane.
#
# an empty set is allowed and draws an empty chart: that is what the caller
# asked for, and it stays recoverable.
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

# --- selection --------------------------------------------------

# the inbound direction of the same contract: the browser reports what the
# user selected, R decides what it means.

#' Canonicalise a viewer selection to a sample range
#'
#' A [gram_plot()] widget reports a completed drag as an
#' `<outputId>_selection` Shiny input carrying `xmin` and `xmax` in the
#' widget's display units -- elapsed seconds, for the x-scale [view_uplot()]
#' builds. Sample index is the canonical key, so the conversion happens here
#' once rather than in every caller.
#'
#' @param cache A `StudyCache`.
#' @param selection The widget's selection input: a list holding `xmin` and
#'   `xmax` in elapsed seconds. `NULL` before anything has been selected.
#' @return A list with `begin` and `end` sample indices delimiting a half-open
#'   range, clamped to the record. `NULL` both when nothing is selected yet and
#'   when the selection collapses to no samples, so a stray click leaves the
#'   caller's current window standing rather than blanking it.
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

# --- verbs, continued -------------------------------------------

# per-channel display config
# series_idx: 1-based channel index (x excluded), matches R habits;
# a faceted adapter maps it to the corresponding panel
gm_set_series <- function(
  proxy,
  series_idx,
  visible = NULL,
  color = NULL,
  label = NULL
) {
  gm_send(
    proxy,
    "gram:set_series",
    list(series = series_idx, visible = visible, color = color, label = label)
  )
}
