# Example data downloader.
#
# `ggm`'s realistic example is the `ort` study: ONE WFDB record made of two
# files that belong together — `ort.hea` (the text header: channels, sampling
# frequency, duration) and `ort.dat` (the binary signal). At ~516 MB the pair is
# far too large to bundle, so it lives as public assets on a GitHub Release and
# is pulled to the per-user cache on first use. This single function is the
# whole story; `piggyback` stays a dev-only *upload* tool (data-raw/upload-ort.R).

#' Download an example study to the local cache
#'
#' Fetch a `ggm` example WFDB record to a local directory, downloading it once
#' and reusing the cached copy thereafter. A WFDB record is a pair of files that
#' together form one dataset — a `.hea` text header and a `.dat` binary signal —
#' and both are fetched. The returned directory drops straight into
#' [open_study()].
#'
#' @param dataset Example record name. Currently only `"ort"` (the default): a
#'   27-channel intracardiac study, 977 Hz, ~2.7 hours (~516 MB).
#' @param dir Directory to cache into. Defaults to the package's per-user cache
#'   (`tools::R_user_dir("ggm", "cache")`), the CRAN-sanctioned location for
#'   downloaded data. Pass e.g. `"data-raw"` to download elsewhere.
#' @param force Re-download even if the files are already present (useful if a
#'   cached copy is suspected truncated).
#' @param quiet Passed to [utils::download.file()]; `FALSE` (default) shows a
#'   progress bar, reassuring for a multi-hundred-MB transfer.
#'
#' @return The path to `dir` (invisibly when a download happened, so a fresh
#'   pull does not dump a path mid-pipeline). The record's `.hea`/`.dat` are
#'   guaranteed present on return, so
#'   `open_study(dataset, cache_example_data(dataset))` always works.
#'
#' @details
#' Each file downloads to a `.part` sidecar and is renamed into place only on
#' success, so an interrupted transfer never leaves a truncated file that later
#' looks "cached". The download timeout is raised for the call (the 60 s default
#' is far too short for these files) and restored on exit.
#'
#' @seealso [open_study()] to open the downloaded record.
#'
#' @examples
#' \dontrun{
#' # Download (once) and open the large ORT study:
#' study <- open_study("ort", cache_example_data("ort"))
#' study
#' }
#' @export
cache_example_data <- function(dataset = "ort",
                               dir = tools::R_user_dir("ggm", "cache"),
                               force = FALSE,
                               quiet = FALSE) {
  records <- "ort" # available example records (each is <name>.hea + <name>.dat)
  if (!is.character(dataset) || length(dataset) != 1L || !dataset %in% records) {
    stop(
      "Unknown example dataset: ", sQuote(dataset), ".\n",
      "  Available: ", paste(sQuote(records), collapse = ", "),
      call. = FALSE
    )
  }

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  files <- paste0(dataset, c(".hea", ".dat")) # the two files that make the record
  dest <- file.path(dir, files)
  need <- force | !file.exists(dest)
  if (!any(need)) {
    return(dir)
  }

  # download.file's 60 s default timeout would abort these large transfers.
  old <- options(timeout = max(getOption("timeout"), 3600L))
  on.exit(options(old), add = TRUE)

  for (i in which(need)) {
    url <- sprintf(
      "https://github.com/shah-in-boots/ggm/releases/download/v0.0.0.9000-data/%s",
      files[i]
    )
    tmp <- paste0(dest[i], ".part")
    ok <- tryCatch(
      utils::download.file(url, tmp, mode = "wb", quiet = quiet) == 0L,
      error = function(e) {
        unlink(tmp)
        stop("Failed to download ", files[i], ": ", conditionMessage(e), call. = FALSE)
      }
    )
    if (!isTRUE(ok) || !file.exists(tmp)) {
      unlink(tmp)
      stop("Download of ", files[i], " failed (no file written).", call. = FALSE)
    }
    file.rename(tmp, dest[i])
  }
  invisible(dir)
}
