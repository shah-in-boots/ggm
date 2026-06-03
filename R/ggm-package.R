#' ggm: A Grammar for Exploring and Presenting Cardiac Electrograms
#'
#' `ggm` (Grammar of Electrograms) is the visualization and interaction layer
#' for cardiac electrophysiology signal data. It builds on the \pkg{EGM} data
#' backend (WFDB-compatible I/O, `signal_table`/`header_table`) and never
#' re-implements what `EGM` already does well.
#'
#' @section The sample/time boundary (D-8):
#' One rule governs the whole data layer: the integer **sample index** is the
#' canonical key for storage, computation, and joins, while **time (seconds)**
#' is the presentation unit. The conversion is exact and free
#' (`time = sample / frequency`). User-facing arguments speak seconds;
#' internal work happens in samples; results carry both. See [time_to_sample()]
#' and [sample_to_time()].
#'
#' @section Where to start:
#' - [open_study()] binds a record + header into a `ggm_study`.
#' - [get_window()] is the windowed-read router that feeds renderers.
#'
#' @keywords internal
#' @importFrom data.table data.table as.data.table rbindlist dcast set setcolorder :=
#' @importFrom arrow read_parquet write_parquet
#' @importFrom jsonlite read_json write_json
"_PACKAGE"

# data.table is used by reference for cheap column work (e.g. appending the
# `time` column to a freshly read signal_table). Declaring awareness keeps `[`
# dispatch correct when ggm objects inherit from data.table.
.datatable.aware <- TRUE

# ---- internal helpers -------------------------------------------------------

# Signal that a function is a deliberate skeleton stub for a named milestone.
# Errors loudly (rather than silently no-op'ing) so a stub is never mistaken
# for working behaviour, and names the milestone so the path forward is obvious.
not_yet_implemented <- function(what, milestone, detail = NULL) {
  msg <- c(
    sprintf("`%s` is not implemented yet (planned for milestone %s).", what, milestone)
  )
  if (!is.null(detail)) msg <- c(msg, detail)
  stop(
    structure(
      class = c("ggm_not_implemented", "error", "condition"),
      list(message = paste(msg, collapse = "\n"), call = sys.call(-1))
    )
  )
}
