# The study object (blueprint S3.4).
#
# `open_study()` is the entry point everything else sits on. It is deliberately
# *lazy*: it reads only the small WFDB header on open and records where the
# signal lives. Signal samples are pulled per-window by `get_window()`, so
# opening a multi-hour study is instant and memory stays bounded.

#' Open a study
#'
#' Bind a WFDB record to a lightweight `ggm_study` object. Only the header is
#' read on open (cheap); signal samples are read on demand by [get_window()].
#'
#' @param record Record name, without file extension (e.g. `"bard-egm"`). The
#'   `.hea`/`.dat` files are expected to share this stem.
#' @param record_dir Directory containing the record's files. Defaults to the
#'   current directory.
#'
#' @return A `ggm_study`: a list with the record location, the parsed `EGM`
#'   `header_table`, and convenience fields pulled from the header
#'   (`frequency` in Hz, `n_samples`, `channels`, `start_time`, and `duration`
#'   in seconds).
#'
#' @details
#' This wraps [EGM::read_header()] and pulls the recording metadata from its
#' `record_line` attribute. The signal store stays canonical in `EGM`; `ggm`
#' only remembers how to reach it.
#'
#' @examples
#' \dontrun{
#' study <- open_study("bard-egm", system.file("extdata", package = "ggm"))
#' study
#' }
#' @export
open_study <- function(record, record_dir = ".") {
  if (!is.character(record) || length(record) != 1L || !nzchar(record)) {
    stop("`record` must be a single non-empty record name.", call. = FALSE)
  }
  if (!dir.exists(record_dir)) {
    stop("`record_dir` does not exist: ", record_dir, call. = FALSE)
  }
  hea <- file.path(record_dir, paste0(record, ".hea"))
  if (!file.exists(hea)) {
    stop(
      "No header found for record '", record, "' in ", normalizePath(record_dir),
      "\n  expected: ", hea,
      call. = FALSE
    )
  }

  header <- EGM::read_header(record, record_dir)
  rl <- attr(header, "record_line")

  frequency <- as.numeric(rl$frequency)
  n_samples <- as.integer(rl$samples)
  check_frequency(frequency)

  structure(
    list(
      record = record,
      record_dir = record_dir,
      header = header,
      frequency = frequency,
      n_samples = n_samples,
      channels = as.character(header$label),
      start_time = rl$start_time,
      duration = sample_to_time(n_samples, frequency),
      # Bound automatically if a sidecar has been built (NULL otherwise).
      pyramid = bind_pyramid(record, record_dir)
    ),
    class = "ggm_study"
  )
}

#' @rdname open_study
#' @param x A `ggm_study` (for `is_study()`) or any object.
#' @return `is_study()` returns a length-one logical.
#' @export
is_study <- function(x) inherits(x, "ggm_study")

#' @export
print.ggm_study <- function(x, ...) {
  cat(sprintf("<ggm_study> '%s'\n", x$record))
  cat(sprintf(
    "  %d channels @ %g Hz · %s samples · %.2f s\n",
    length(x$channels), x$frequency,
    format(x$n_samples, big.mark = ","), x$duration
  ))
  cat("  channels:", truncate_labels(x$channels), "\n")
  if (is.null(x$pyramid)) {
    cat("  pyramid: none — build_pyramid() to enable fast overview\n")
  } else {
    tiers <- x$pyramid$manifest$tiers$samples_per_bucket
    cat(sprintf("  pyramid: %d tiers (%s)\n", length(tiers), paste(tiers, collapse = ", ")))
  }
  cat("  dir:", x$record_dir, "\n")
  invisible(x)
}

# Compact channel listing for printing: show the first few, then "... (+N more)".
truncate_labels <- function(labels, n = 8L) {
  if (length(labels) <= n) return(paste(labels, collapse = ", "))
  paste0(
    paste(labels[seq_len(n)], collapse = ", "),
    sprintf(" ... (+%d more)", length(labels) - n)
  )
}
