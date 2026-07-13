test_that("study_cache opens a WFDB record group", {
  record <- system.file("extdata", "bard-egm.hea", package = "ggm")
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
  record <- system.file("extdata", "bard-egm.hea", package = "ggm")
  skip_if(record == "", "bundled WFDB example not installed")

  cache_dir <- tempfile("ggm-cache-")
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

  raw <- as.data.frame(read_study_signal(cache, 0, 0.064, channels = "I"))
  overview <- read_cache_overview(cache, 0, 0.064, channels = "I", level = 1)

  expect_equal(overview$value[overview$statistic == "first"], raw$I[[1]])
  expect_equal(overview$value[overview$statistic == "min"], min(raw$I))
  expect_equal(overview$value[overview$statistic == "max"], max(raw$I))
  expect_equal(overview$value[overview$statistic == "last"], raw$I[[nrow(raw)]])

  raw_view <- read_study_viewport(cache, 0, 0.01, channels = "I", pixel_width = 500)
  expect_equal(raw_view$resolution, "raw")
  expect_equal(names(raw_view$data), c("sample", "I"))

  overview_view <- read_study_viewport(
    cache,
    0,
    3,
    channels = "I",
    pixel_width = 10,
    resolution = "overview"
  )
  expect_equal(overview_view$level, 1L)
  expect_named(overview_view$data, c("sample", "time", "channel", "value", "statistic"))
})
