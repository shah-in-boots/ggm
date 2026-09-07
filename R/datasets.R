#' Download an example study to the local cache
#'
#' Fetch a `gram` example WFDB record — the `.hea` header and the `.dat` signal
#' — to a local directory, downloading it once and reusing the cached copy
#' thereafter. Downloads use the \pkg{piggyback} package.
#'
#' @param dataset Example record name. Currently only `"ort"` (the default): a
#'   27-channel intracardiac study, 977 Hz, ~2.7 hours (~516 MB).
#' @param dir Directory to cache into. Defaults to the package's per-user cache
#'   (`tools::R_user_dir("gram", "cache")`).
#' @param force Re-download even if the files are already cached.
#' @param quiet Suppress piggyback's download progress bar.
#' @return The path to `dir`, invisibly when a download happened.
#' @family cache
#' @export
cache_study_data <- function(dataset = "ort",
                               dir = tools::R_user_dir("gram", "cache"),
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
    repo = "shah-in-boots/gram",
    tag = "v0.0.0.9000-data",
    overwrite = TRUE,
    use_timestamps = !force, # force => re-fetch regardless of local timestamps
    show_progress = !quiet
  )
  invisible(dir)
}
