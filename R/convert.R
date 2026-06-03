# The sample <-> time boundary (blueprint S3.0, decision D-8).
#
# Sample index (integer) is canonical for storage, computation, and joins.
# Time (seconds) is the display unit. These two helpers are the *only* place
# the conversion lives, so the rest of the package can move between the two
# freely and exactly.

#' Convert between sample index and time
#'
#' The sample index (an integer count of samples from the start of the record)
#' is the canonical key used for storage and joins; time in seconds is the
#' display unit. Conversion is exact given the recording's sampling frequency:
#' `time = sample / frequency` and `sample = round(time * frequency)`.
#'
#' @param time Numeric vector of times, in **seconds**.
#' @param sample Numeric (integer) vector of **sample indices**.
#' @param frequency Sampling frequency in Hz (samples per second). A single
#'   positive number, typically `study$frequency`.
#'
#' @return
#' - `time_to_sample()`: an integer vector of sample indices (rounded).
#' - `sample_to_time()`: a double vector of times in seconds.
#'
#' @details
#' `time_to_sample()` rounds to the nearest sample because a time need not land
#' exactly on a sample boundary; `sample_to_time()` is exact. Round-tripping a
#' valid sample index (`sample_to_time()` then `time_to_sample()`) returns the
#' original index.
#'
#' @examples
#' time_to_sample(c(0, 1, 1.5), frequency = 1000)
#' sample_to_time(c(0L, 1000L, 1500L), frequency = 1000)
#'
#' @name convert
NULL

#' @rdname convert
#' @export
time_to_sample <- function(time, frequency) {
  check_frequency(frequency)
  if (!is.numeric(time)) stop("`time` must be numeric (seconds).", call. = FALSE)
  as.integer(round(time * frequency))
}

#' @rdname convert
#' @export
sample_to_time <- function(sample, frequency) {
  check_frequency(frequency)
  if (!is.numeric(sample)) stop("`sample` must be numeric (sample indices).", call. = FALSE)
  as.double(sample) / frequency
}

# Shared validation for the conversion frequency. Kept internal and strict so
# bad frequencies fail at the boundary rather than producing silent nonsense.
check_frequency <- function(frequency) {
  if (!is.numeric(frequency) || length(frequency) != 1L ||
      is.na(frequency) || frequency <= 0) {
    stop("`frequency` must be a single positive number (Hz).", call. = FALSE)
  }
  invisible(frequency)
}
