tracingSpecVersion <- 1L

# supported operation types, in the order the compiler emits them
tracingOps <- c("reveal", "arrow", "emphasize")


# class -----------------------------------------------------------------

#' A signal window and the animation drawn over it
#'
#' Create with [tracing()]. Verbs such as [reveal()] and [add_arrow()]
#' append operations; the operation list is the animation specification.
#'
#' @param stem Record stem the window was read from.
#' @param sample_rate Sampling frequency in Hz.
#' @param samples Sample indices of the window, in order.
#' @param channels Channel labels, top lane first.
#' @param values Named list of numeric vectors, one per channel.
#' @param units Physical unit of `values`.
#' @param ops Ordered list of animation operations.
#'
#' @noRd
Tracing <- S7::new_class(
  "Tracing",
  properties = list(
    stem        = S7::class_character,
    sample_rate = S7::class_double,
    samples     = S7::class_double,
    channels    = S7::class_character,
    values      = S7::class_list,
    units       = S7::class_character,
    ops         = S7::class_list
  ),
  validator = function(self) {
    if (length(self@channels) == 0L) {
      "@channels must name at least one channel"
    } else if (!setequal(names(self@values), self@channels)) {
      "@values must hold exactly one vector per channel"
    } else if (any(lengths(self@values) != length(self@samples))) {
      "@values vectors must be as long as @samples"
    } else {
      NULL
    }
  }
)

S7::method(print, Tracing) <- function(x, ...) {
  span <- range(x@samples)
  cat("<Tracing> ", x@stem, "\n", sep = "")
  cat("  samples:  ", span[[1L]], "-", span[[2L]],
      " (", length(x@samples), " points)\n", sep = "")
  cat("  seconds:  ", format(span[[1L]] / x@sample_rate, digits = 4), "-",
      format(span[[2L]] / x@sample_rate, digits = 4), "\n", sep = "")
  cat("  channels: ", paste(x@channels, collapse = ", "), "\n", sep = "")

  if (length(x@ops) == 0L) {
    cat("  script:   [no operations]\n")
  } else {
    cat("  script:\n")
    for (i in seq_along(x@ops)) {
      op <- x@ops[[i]]
      cat("    ", i, ". ", op$type,
          if (!is.null(op$label)) paste0("  \"", op$label, "\"") else "",
          "\n", sep = "")
    }
  }
  invisible(x)
}


# constructor -----------------------------------------------------------

#' Open a signal window as a tracing
#'
#' Reads one window from the canonical signal and returns a `Tracing` with
#' an empty script. Verbs append operations to it.
#'
#' @param cache A `StudyCache` from [study_cache()].
#' @inheritParams read_study_signal
#' @param max_points Largest number of points kept per channel. Longer
#'   windows are decimated by a fixed stride, which can drop a narrow
#'   deflection; keep presentation windows short rather than raising this.
#' @return A `Tracing`.
#' @family tracing
#' @export
tracing <- function(cache,
                    begin = NULL,
                    end = NULL,
                    interval = NULL,
                    channels = NULL,
                    units = c("physical", "digital"),
                    max_points = 2000) {
  units <- match.arg(units)
  if (missing(end) && missing(interval) && is.null(end) && is.null(interval)) {
    interval <- 2
  }

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
    stop("the window did not contain any signal channels", call. = FALSE)
  }

  keep <- tr_decimation_index(nrow(signal), max_points)
  if (length(keep) < nrow(signal)) {
    warning(
      "window decimated from ", nrow(signal), " to ", length(keep),
      " points per channel; narrow deflections may be lost",
      call. = FALSE
    )
  }

  Tracing(
    stem = cache@stem,
    sample_rate = cache@sample_rate,
    samples = as.double(signal$sample[keep]),
    channels = channelNames,
    values = lapply(signal[keep, channelNames, drop = FALSE], as.double),
    units = units,
    ops = list()
  )
}

# even stride that always keeps the first and last point
tr_decimation_index <- function(n, max_points) {
  if (!is.finite(max_points) || max_points < 2) {
    stop("`max_points` must be at least 2", call. = FALSE)
  }
  if (n <= max_points) {
    return(seq_len(n))
  }
  unique(c(round(seq(1, n, length.out = max_points)), n))
}


# feature references ----------------------------------------------------

#' Refer to a point on a channel
#'
#' `at()` names a sample on a channel so a verb can resolve it to a position.
#'
#' @param sample Sample index.
#' @param channel Channel label.
#' @return A `gram_at` reference.
#' @family tracing
#' @export
at <- function(sample, channel) {
  if (length(sample) != 1L || !is.numeric(sample) || !is.finite(sample)) {
    stop("`sample` must be a single finite number", call. = FALSE)
  }
  if (length(channel) != 1L || !is.character(channel)) {
    stop("`channel` must be a single channel label", call. = FALSE)
  }
  structure(
    list(sample = as.double(sample), channel = channel),
    class = "gram_at"
  )
}

# resolve a reference against a tracing, failing clearly when it cannot be
tr_resolve_at <- function(x, ref, arg) {
  if (!inherits(ref, "gram_at")) {
    stop("`", arg, "` must be a point from at()", call. = FALSE)
  }
  if (!ref$channel %in% x@channels) {
    stop(
      "`", arg, "` names channel \"", ref$channel,
      "\", which is not in this tracing (have: ",
      paste(x@channels, collapse = ", "), ")",
      call. = FALSE
    )
  }
  span <- range(x@samples)
  if (ref$sample < span[[1L]] || ref$sample > span[[2L]]) {
    stop(
      "`", arg, "` is at sample ", ref$sample,
      ", outside this tracing's window (", span[[1L]], "-", span[[2L]], ")",
      call. = FALSE
    )
  }
  ref
}


# verbs -----------------------------------------------------------------

tr_append_op <- function(x, op) {
  x@ops <- c(x@ops, list(op))
  x
}

#' Draw the traces on, like pen on paper
#'
#' @param x A `Tracing`.
#' @param duration Milliseconds for one channel to finish drawing.
#' @param stagger Milliseconds each channel waits behind the one above it.
#' @return The tracing, with the operation appended.
#' @family tracing verbs
#' @export
reveal <- function(x, duration = 1200, stagger = 180) {
  stopifnot(S7::S7_inherits(x, Tracing))
  tr_append_op(x, list(
    type = "reveal",
    duration = as.double(duration),
    stagger = as.double(stagger)
  ))
}

#' Draw an arrow between two points
#'
#' @param x A `Tracing`.
#' @param from,to Points from [at()].
#' @param label Optional text drawn at the arrow's midpoint.
#' @param duration Milliseconds for the arrow to draw.
#' @return The tracing, with the operation appended.
#' @family tracing verbs
#' @export
add_arrow <- function(x, from, to, label = NULL, duration = 600) {
  stopifnot(S7::S7_inherits(x, Tracing))
  tr_append_op(x, list(
    type = "arrow",
    from = tr_resolve_at(x, from, "from"),
    to = tr_resolve_at(x, to, "to"),
    label = label,
    duration = as.double(duration)
  ))
}

#' Mark a point for emphasis
#'
#' @param x A `Tracing`.
#' @param target A point from [at()].
#' @param label Optional text drawn beside the mark.
#' @param duration Milliseconds for the mark to appear.
#' @return The tracing, with the operation appended.
#' @family tracing verbs
#' @export
emphasize <- function(x, target, label = NULL, duration = 450) {
  stopifnot(S7::S7_inherits(x, Tracing))
  tr_append_op(x, list(
    type = "emphasize",
    target = tr_resolve_at(x, target, "target"),
    label = label,
    duration = as.double(duration)
  ))
}
