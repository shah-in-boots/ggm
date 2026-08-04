# helper-gram.R -------------------------------------------------------
# Fixtures shared by every test file. testthat sources helper-*.R before
# any test runs, so a file reaches these without repeating them.
#
# The suite is built on the bundled `bard-egm` record: 14 channels of
# 1000 Hz signal, 3522 samples, so 3.5 seconds. It is small enough to
# commit, which is the whole reason it is the fixture. The large `ort`
# record the acceptance gates in design.qmd name is pulled at runtime by
# cache_study_data() and is deliberately not part of this suite -- no
# test should reach the network.
#
# Each cache gets a directory of its own. study_cache() attaches any
# manifest it finds in cache_dir, so a shared tempdir() would let a cache
# built by one test silently change what a later test opens.

# Returns "" when the bundled record is absent, which is what
# skip_if_no_record() tests for. Do not shorten this to
# file.path(system.file(dir), file): that spelling pastes a separator onto
# whatever system.file() gave back, so it always returns a non-empty path
# and the absent record can no longer be detected -- the suite then fails
# somewhere further in instead of skipping here.
bard_record <- function(ext = "hea") {
  system.file("extdata", paste0("bard-egm.", ext), package = "gram")
}

skip_if_no_record <- function() {
  testthat::skip_if(
    !nzchar(bard_record("hea")) || !nzchar(bard_record("dat")),
    "bundled WFDB example record not installed"
  )
}

# A StudyCache over the bundled record, with its own cache directory.
demo_cache <- function(cache_dir = tempfile("gram-cache-")) {
  skip_if_no_record()
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  study_cache(bard_record("hea"), cache_dir = cache_dir)
}

# A StudyCache whose overview cache has been built. Kept small on purpose:
# 64-sample buckets over 3522 samples give two levels, which is the
# minimum that still exercises level selection. `cache_dir` is exposed so
# a test can reopen the same cache after tampering with it.
demo_built_cache <- function(cache_dir = tempfile("gram-cache-"), ...) {
  cache <- demo_cache(cache_dir)
  suppressMessages(build_study_cache(
    cache,
    bucket_samples = 64,
    level_factor = 4,
    chunk_seconds = 1,
    overwrite = TRUE,
    ...
  ))
}

# Reopen a study from disk, which is what re-runs gm_attach_manifest() and so
# re-checks the manifest against the record.
reopen_cache <- function(cache) {
  study_cache(bard_record("hea"), cache_dir = cache@cache_dir)
}

# Rewrite named fields of a built cache's manifest in place. This is how
# the gm_attach_manifest() guards are reached without shipping a second cache
# format or mutating the installed record.
tamper_manifest <- function(cache, ...) {
  fields <- list(...)
  manifest <- jsonlite::read_json(cache@manifest_path, simplifyVector = TRUE)
  manifest[names(fields)] <- fields
  jsonlite::write_json(
    manifest,
    cache@manifest_path,
    auto_unbox = TRUE,
    digits = NA,
    pretty = TRUE
  )
  invisible(cache)
}

# A two-lane tracing over the first half second.
demo_tracing <- function(cache = demo_cache()) {
  tracing(
    cache,
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  )
}
