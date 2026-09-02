test_that("study_cache opens a WFDB record group", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  expect_true(any(grepl("StudyCache$", class(cache))))
  expect_equal(cache@stem, "bard-egm")
  expect_equal(cache@sample_rate, 1000)
  expect_equal(cache@n_samples, 3522)
  expect_length(cache@channels, 14)
  expect_true("qrs" %in% cache_annotators(cache))
  expect_true(file.exists(cache_paths(cache)[["raw"]]))
  expect_true(file.exists(cache_paths(cache)[["header"]]))
})

test_that("study reads use EGM time-window conventions", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

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


# refusals --------------------------------------------------------------

test_that("study_cache refuses an incomplete WFDB record group", {
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
})

test_that("study_cache refuses a path that is not one path", {
  expect_error(study_cache(character()), "single non-empty path")
  expect_error(study_cache(c("a.hea", "b.hea")), "single non-empty path")
  expect_error(study_cache(""), "single non-empty path")
})

test_that("study_cache refuses an annotator that is not on disk", {
  expect_error(
    study_cache(
      system.file("extdata", "bard-egm.hea", package = "gram"),
      annotators = "nosuch"
    ),
    "requested annotation file(s) not found: bard-egm.nosuch",
    fixed = TRUE
  )

  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    annotators = "qrs"
  )
  expect_equal(cache_annotators(cache), "qrs")
})
