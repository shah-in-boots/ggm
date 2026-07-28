test_that("study_cache opens a WFDB record group", {
  record <- system.file("extdata", "bard-egm.hea", package = "gram")
  skip_if(record == "", "bundled WFDB example not installed")

  cache <- study_cache(record, cache_dir = tempdir())

  expect_true(any(grepl("StudyCache$", class(cache))))
  expect_equal(cache@stem, "bard-egm")
  expect_equal(cache@sample_rate, 1000)
  expect_equal(cache@n_samples, 3522)
  expect_length(cache@channels, 14)
  expect_true("qrs" %in% cache_annotators(cache))
  expect_true(file.exists(cache_paths(cache)[["raw"]]))
  expect_true(file.exists(cache_paths(cache)[["header"]]))
})

test_that("build_study_cache writes bucket extrema from WFDB reads", {
  record <- system.file("extdata", "bard-egm.hea", package = "gram")
  skip_if(record == "", "bundled WFDB example not installed")

  cache_dir <- tempfile("gram-cache-")
  dir.create(cache_dir)
  cache <- study_cache(record, cache_dir = cache_dir)

  cache <- suppressMessages(build_study_cache(
    cache,
    bucket_samples = 64,
    level_factor = 4,
    chunk_seconds = 1,
    overwrite = TRUE
  ))

  expect_true(cache_is_built(cache))
  expect_true(file.exists(cache_paths(cache)[["cache"]]))
  expect_true(file.exists(cache_paths(cache)[["manifest"]]))
  expect_equal(cache@levels$level, c(0L, 1L))

  raw <- as.data.frame(read_study_signal(
    cache,
    begin = "00:00:00",
    interval = "64 ms",
    channels = "I"
  ))
  overview <- read_cache_overview(
    cache,
    begin = "00:00:00",
    interval = "64 ms",
    channels = "I",
    level = 1
  )

  expect_equal(overview$value[overview$statistic == "first"], raw$I[[1]])
  expect_equal(overview$value[overview$statistic == "min"], min(raw$I))
  expect_equal(overview$value[overview$statistic == "max"], max(raw$I))
  expect_equal(overview$value[overview$statistic == "last"], raw$I[[nrow(raw)]])

  raw_view <- read_study_viewport(
    cache,
    begin = "00:00:00",
    interval = "10 ms",
    channels = "I",
    pixel_width = 500
  )
  expect_equal(raw_view$resolution, "raw")
  expect_equal(names(raw_view$data), c("sample", "I"))

  overview_view <- read_study_viewport(
    cache,
    begin = "00:00:00",
    interval = 3,
    channels = "I",
    pixel_width = 10,
    resolution = "overview"
  )
  expect_equal(overview_view$level, 1L)
  expect_named(overview_view$data, c("sample", "time", "channel", "value", "statistic"))
})

test_that("study reads use EGM time-window conventions", {
  record <- system.file("extdata", "bard-egm.hea", package = "gram")
  cache <- study_cache(record, cache_dir = tempdir())

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
