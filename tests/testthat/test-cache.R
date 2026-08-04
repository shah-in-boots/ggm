# demo_cache() and demo_built_cache() come from helper-gram.R


# fixture contract ------------------------------------------------------

test_that("the record fixture reports an absent record as an empty path", {
  # skip_if_no_record() rests on this: system.file() returns "" for a file it
  # cannot find, so the guard is able to fire. The shorter
  # file.path(system.file(dir), file) spelling always yields a non-empty
  # path, which is why the fixture does not use it -- with that spelling the
  # suite fails obscurely on a machine without the bundled data instead of
  # skipping.
  expect_identical(system.file("extdata", "no-record.dat", package = "gram"), "")
  expect_true(nzchar(file.path("", "no-record.dat")))

  expect_true(nzchar(bard_record("hea")))
  expect_true(nzchar(bard_record("dat")))
})

test_that("each fixture cache gets a cache directory of its own", {
  # study_cache() attaches whatever manifest it finds in cache_dir, so a
  # shared directory would let a cache built by one test decide what a later
  # test opens, and the suite would pass or fail by file order.
  built <- demo_built_cache()
  fresh <- demo_cache()

  expect_false(identical(built@cache_dir, fresh@cache_dir))
  expect_true(cache_is_built(built))
  expect_false(cache_is_built(fresh))
})


# opening and reading ---------------------------------------------------

test_that("study_cache opens a WFDB record group", {
  cache <- demo_cache()

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
  cache <- demo_built_cache()

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
  cache <- demo_cache()

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
  skip_if_no_record()

  # a .hea with no sibling .dat is not a record, however well formed it is
  lone <- tempfile("gram-lone-")
  dir.create(lone)
  file.copy(bard_record("hea"), file.path(lone, "bard-egm.hea"))

  expect_error(
    study_cache(file.path(lone, "bard-egm.hea"), cache_dir = lone),
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
  skip_if_no_record()

  expect_error(
    study_cache(
      bard_record("hea"),
      cache_dir = tempfile("gram-cache-"),
      annotators = "nosuch"
    ),
    "requested annotation file(s) not found: bard-egm.nosuch",
    fixed = TRUE
  )

  # the sidecar that does exist is accepted, and named by its extension
  cache <- study_cache(
    bard_record("hea"),
    cache_dir = tempfile("gram-cache-"),
    annotators = "qrs"
  )
  expect_equal(cache_annotators(cache), "qrs")
})

test_that("build_study_cache refuses geometry it cannot honour", {
  cache <- demo_cache()

  expect_error(
    build_study_cache(cache, bucket_samples = 1),
    "`bucket_samples` must be an integer >= 2",
    fixed = TRUE
  )
  expect_error(
    build_study_cache(cache, level_factor = 1),
    "`level_factor` must be an integer >= 2",
    fixed = TRUE
  )
  expect_error(
    build_study_cache(cache, max_levels = 0),
    "`max_levels` must be an integer >= 1",
    fixed = TRUE
  )
  expect_error(
    build_study_cache(cache, chunk_seconds = 0),
    "`chunk_seconds` must be a positive number",
    fixed = TRUE
  )
  expect_error(
    build_study_cache(cache, chunk_seconds = -1),
    "`chunk_seconds` must be a positive number",
    fixed = TRUE
  )
})


# cache invalidation ----------------------------------------------------
#
# The design's acceptance gates require the cache to be versioned and
# invalidated by the record fingerprint. These reach those guards by
# rewriting a built manifest, which is cheaper than shipping a second
# cache format and does not touch the installed record.

test_that("build_study_cache attaches an existing cache instead of rebuilding", {
  cache <- demo_built_cache()
  builtAt <- cache@created_at

  expect_message(again <- build_study_cache(cache), "already built")
  expect_equal(again@created_at, builtAt)
})

test_that("a cache manifest from another format version is refused", {
  cache <- demo_built_cache()
  tamper_manifest(cache, version = 999L)

  expect_error(
    reopen_cache(cache),
    "cache manifest version 999 is not supported"
  )
})

test_that("a cache built by another algorithm is refused", {
  cache <- demo_built_cache()
  tamper_manifest(cache, algorithm = "lttb-v2")

  # the algorithm is sQuote()d, so the quote characters depend on the locale
  expect_error(reopen_cache(cache), "cache algorithm .+lttb-v2.+ is not supported")
})

test_that("a manifest without its parquet warns and leaves the study unbuilt", {
  cache <- demo_built_cache()
  unlink(cache@cache_path)

  expect_warning(
    reopened <- reopen_cache(cache),
    "manifest exists but cache parquet is missing"
  )
  expect_false(cache_is_built(reopened))
})

test_that("a record that changed since its cache was built warns", {
  cache <- demo_built_cache()
  tamper_manifest(cache, fingerprint = "stale-fingerprint")

  expect_warning(
    reopened <- reopen_cache(cache),
    "record changed since cache was built"
  )

  # advisory, not a refusal: the levels still attach so the stale overview
  # remains readable until the caller rebuilds
  expect_true(cache_is_built(reopened))
})
