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

# Large ORT record (~516 MB), served as a GitHub Release asset. Routes through
# the package's own downloader so tests exercise the same path users do; a
# download failure (e.g. the data release isn't published yet) becomes a skip.
ort_record_dir <- function() {
  cache <- tools::R_user_dir("ggm", "cache")
  if (!all(file.exists(file.path(cache, c("ort.dat", "ort.hea"))))) {
    skip_if_offline()
    tryCatch(
      cache_example_data("ort", dir = cache, quiet = TRUE),
      error = function(e) skip(paste("ORT data unavailable:", conditionMessage(e)))
    )
  }
  cache
}

open_ort_study <- function() {
  skip_if_not_installed("EGM")
  open_study("ort", ort_record_dir())
}
