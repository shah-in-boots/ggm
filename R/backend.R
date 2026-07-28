# backend.R -- plotting contract, backend-neutral
#
# all gram code talks to plots through these verbs only.
# each verb sends a "gram:*" custom message; gram-dispatch.js
# routes it to whichever adapter owns the instance.
#
# verbs: set_data, set_viewport, set_series
# (annotations verb added later, same pattern)
#
# units: viewport always in domain units (time or sample idx),
# never pixels. backend converts internally.

# --- proxy ------------------------------------------------------

# handle to a live widget in a running shiny session.
# no-op outside shiny (standalone tier-1 tests use renderValue only)
#
# id: outputId of the widget
gram_proxy <- function(id, session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) stop("gram_proxy requires a shiny session")
  structure(
    list(id = session$ns(id), session = session),
    class = "gram_proxy"
  )
}

# internal: send one message on a gram channel
# payload must be a named list; id injected here
gram_send <- function(proxy, channel, payload) {
  stopifnot(inherits(proxy, "gram_proxy"))
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
gram_set_data <- function(proxy, columns) {
  gram_send(proxy, "gram:set_data", list(columns = lapply(columns, I)))
}

# set visible x (and optionally y) range in domain units
gram_set_viewport <- function(proxy, xmin, xmax, ymin = NULL, ymax = NULL) {
  gram_send(
    proxy,
    "gram:set_viewport",
    list(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)
  )
}

# per-channel display config
# series_idx: 1-based channel index (x excluded), matches R habits;
# a faceted adapter maps it to the corresponding panel
gram_set_series <- function(
  proxy,
  series_idx,
  visible = NULL,
  color = NULL,
  label = NULL
) {
  gram_send(
    proxy,
    "gram:set_series",
    list(series = series_idx, visible = visible, color = color, label = label)
  )
}
