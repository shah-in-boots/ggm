# The suite is built on the bundled `bard-egm` record: 14 channels at
# 1000 Hz, 3522 samples. Every build goes to its own temporary cache_dir:
# system.file("extdata") is writable, so a default build would drop gram
# files into the installed package, and a shared directory would let one
# test's build decide what a later test opens.
#
# This file covers the handle. The overview pyramid its manifest describes is
# covered in test-overview.R.

# opening and reading ---------------------------------------------------

test_that("study_cache opens a WFDB record group", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )

  expect_true(any(grepl("StudyCache$", class(cache))))
  expect_equal(cache@stem, "bard-egm")
  expect_equal(cache@sample_rate, 1000)
  expect_equal(cache@n_samples, 3522)
  expect_length(cache@channels, 14)
  expect_true("qrs" %in% cache_annotators(cache))
  expect_true(file.exists(cache_paths(cache)[["data"]]))
  expect_true(file.exists(cache_paths(cache)[["header"]]))
  expect_false(file.exists(cache_paths(cache)[["manifest"]]))
  expect_output(print(cache), "overview:\\s*\\[not built\\]")
})

test_that("study reads use EGM time-window conventions", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )

  byClock <- read_study_signal(
    cache,
    begin = "00:00:00.010",
    interval = "10 ms",
    channels = "I"
  )
  byElapsed <- read_study_signal(
    cache,
    begin = as.difftime(0.01, units = "secs"),
    interval = 0.01,
    channels = "I"
  )

  expect_identical(byClock$sample, 10:19)
  expect_identical(byElapsed$sample, byClock$sample)

  startTime <- attr(cache@header, "record_line")$start_time
  if (inherits(startTime, "POSIXt") && !is.na(startTime)) {
    byAbsoluteTime <- read_study_signal(
      cache,
      begin = startTime + 0.01,
      interval = "10 ms",
      channels = "I"
    )
    expect_identical(byAbsoluteTime$sample, byClock$sample)
  }

  expect_error(
    read_study_signal(cache, begin = 0.01, interval = 0.01),
    "character timestamp"
  )

  empty <- read_study_signal(
    cache,
    begin = "00:00:00.010",
    end = "00:00:00.010",
    channels = "I"
  )
  expect_equal(nrow(empty), 0L)

  clamped <- read_study_signal(
    cache,
    begin = "00:00:03.500",
    interval = "30s",
    channels = "I"
  )
  expect_identical(clamped$sample, 3500:3521)
})


# reopening -------------------------------------------------------------

test_that("a reopened record reads gram's own files as cache, not as annotators, and notices the record changed", {
  # both claims need the same fixture: a record in a writable directory that
  # has been built, so gram's files sit beside the record's own
  dir <- tempfile("gram-record-")
  dir.create(dir)
  for (ext in c("hea", "dat", "qrs")) {
    file.copy(
      system.file("extdata", paste0("bard-egm.", ext), package = "gram"),
      file.path(dir, paste0("bard-egm.", ext))
    )
  }
  cache <- study_cache(file.path(dir, "bard-egm.hea"))
  build_overview(cache)
  expect_equal(dirname(cache_paths(cache)[["cache"]]), normalizePath(dir, winslash = "/"))

  # `<stem>.gram.*` is gram's, so it is the cache and never an annotator
  reopened <- study_cache(file.path(dir, "bard-egm.hea"))
  expect_equal(cache_annotators(reopened), "qrs")
  expect_true("cache" %in% names(cache_paths(reopened)))
  # opening from the manifest or the table still names the record
  expect_equal(study_cache(file.path(dir, "bard-egm.gram.json"))@stem, "bard-egm")

  # a record that changed since its build reads as not built, never as current
  Sys.setFileTime(file.path(dir, "bard-egm.dat"), Sys.time() + 60)
  stale <- study_cache(file.path(dir, "bard-egm.hea"))

  expect_output(print(stale), "overview:   stale", fixed = TRUE)
  expect_false("cache" %in% names(cache_paths(stale)))
  expect_error(
    read_viewport(stale, list(begin = 0, end = 3522), width_px = 100),
    "not built or stale"
  )

  build_overview(stale, rebuild = TRUE)
  expect_equal(read_viewport(stale, list(begin = 0, end = 3522), width_px = 100)$level, 1L)
})


# refusals --------------------------------------------------------------

test_that("study_cache refuses a record group it cannot open", {
  # a .hea with no sibling .dat is not a record, however well formed it is
  lone <- tempfile("gram-lone-")
  dir.create(lone)
  file.copy(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    file.path(lone, "bard-egm.hea")
  )
  expect_error(
    study_cache(file.path(lone, "bard-egm.hea")),
    "not a complete WFDB record group, missing: bard-egm.dat",
    fixed = TRUE
  )

  # one path means one path, not none and not several
  expect_error(study_cache(character()), "single non-empty path")
  expect_error(study_cache(c("a.hea", "b.hea")), "single non-empty path")
  expect_error(study_cache(""), "single non-empty path")

  # a requested annotator that is not on disk is an error, not an empty slot
  expect_error(
    study_cache(
      system.file("extdata", "bard-egm.hea", package = "gram"),
      cache_dir = tempfile("gram-cache-"),
      annotators = "nosuch"
    ),
    "requested annotation file(s) not found: bard-egm.nosuch",
    fixed = TRUE
  )
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-"),
    annotators = "qrs"
  )
  expect_equal(cache_annotators(cache), "qrs")
})
