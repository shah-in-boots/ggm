# Example data downloader.
#
# `ggm`'s realistic example is the `ort` study: ONE WFDB record made of two
# files that belong together — `ort.hea` (the text header: channels, sampling
# frequency, duration) and `ort.dat` (the ~516 MB binary signal). The pair is
# far too large to bundle, so it lives as public assets on a GitHub Release and
# is pulled to the per-user cache on first use.
#
# Download uses `piggyback` — the same tool `data-raw/upload-ort.R` uses to push
# the assets, so upload and download share one mechanism. piggyback is a
# *Suggests*, not an Imports: this function checks for it at call time, so users
# who never pull the demo don't carry its dependency tree. The cheap
# "already cached?" check runs before any piggyback / GitHub-API call, so
# re-opening an already-downloaded study costs nothing.

#' Download an example study to the local cache
#'
#' Fetch a `ggm` example WFDB record to a local directory, downloading it once
#' and reusing the cached copy thereafter. A WFDB record is a pair of files that
#' together form one dataset — a `.hea` text header and a `.dat` binary signal —
#' and both are fetched. The returned directory drops straight into
#' [open_study()].
#'
#' Downloads use the \pkg{piggyback} package (the same tool that publishes the
#' assets). Install it with `install.packages("piggyback")` if prompted.
#'
#' @param dataset Example record name. Currently only `"ort"` (the default): a
#'   27-channel intracardiac study, 977 Hz, ~2.7 hours (~516 MB).
#' @param dir Directory to cache into. Defaults to the package's per-user cache
#'   (`tools::R_user_dir("ggm", "cache")`), the CRAN-sanctioned location for
#'   downloaded data. Pass e.g. `"data-raw"` to download elsewhere.
#' @param force Re-download even if the files are already cached (useful if a
#'   cached copy is suspected truncated or stale).
#' @param quiet Suppress piggyback's download progress bar.
#'
#' @return The path to `dir` (invisibly when a download happened, so a fresh
#'   pull does not dump a path mid-pipeline). The record's `.hea`/`.dat` are
#'   guaranteed present on return, so
#'   `open_study(dataset, cache_example_data(dataset))` always works.
#'
#' @details
#' If the record's files are already present in `dir`, this returns immediately
#' without contacting GitHub. Otherwise it delegates to
#' [piggyback::pb_download()], which fetches only the missing files (or, with
#' `force`, re-fetches them regardless of timestamps).
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

  files <- paste0(dataset, c(".hea", ".dat")) # the two files that make the record
  if (!force && all(file.exists(file.path(dir, files)))) {
    return(dir) # cached: no piggyback / GitHub-API call needed
  }

  if (!requireNamespace("piggyback", quietly = TRUE)) {
    stop(
      "Downloading example data needs the 'piggyback' package.\n",
      "  Install it with: install.packages(\"piggyback\")",
      call. = FALSE
    )
  }

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  piggyback::pb_download(
    file = files,
    dest = dir,
    repo = "shah-in-boots/ggm",
    tag = "v0.0.0.9000-data",
    overwrite = TRUE,
    use_timestamps = !force, # force => re-fetch regardless of local timestamps
    show_progress = !quiet
  )
  invisible(dir)
}
