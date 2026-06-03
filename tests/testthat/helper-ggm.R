# Shared fixtures for the bundled WFDB sample record (inst/extdata/bard-egm.*):
# 14 channels, 1000 Hz, 3522 samples (~3.5 s).

test_record <- function() "bard-egm"

test_record_dir <- function() system.file("extdata", package = "ggm")

# Open the bundled study, skipping the test cleanly if EGM (the data backend)
# is unavailable in the test environment.
open_test_study <- function() {
  skip_if_not_installed("EGM")
  open_study(test_record(), test_record_dir())
}

# Copy the bundled record into a fresh temp dir so pyramid sidecars can be built
# and torn down without touching inst/extdata. Cleaned up with the test env.
local_bard_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  src <- test_record_dir()
  files <- list.files(src, pattern = "^bard-egm\\.", full.names = TRUE)
  file.copy(files, dir)
  dir
}

# Large ORT record (~1 GB), stored as a GitHub Release asset via piggyback.
# Downloads once to the user cache and reuses it on subsequent runs.
ort_record_dir <- function() {
  cache <- tools::R_user_dir("ggm", "cache")
  files <- c("ort.dat", "ort.hea")
  missing <- !file.exists(file.path(cache, files))

  if (any(missing)) {
    skip_if_not_installed("piggyback")
    skip_if_offline()
    dir.create(cache, recursive = TRUE, showWarnings = FALSE)
    piggyback::pb_download(
      files[missing],
      dest = cache,
      repo = "shah-in-boots/ggm",
      tag = "v0.0.0.9000-data"
    )
  }

  cache
}

open_ort_study <- function() {
  skip_if_not_installed("EGM")
  open_study("ort", ort_record_dir())
}
