# The suite is built on the bundled `bard-egm` record: 14 channels at
# 1000 Hz, 3522 samples, so 55 full 64-sample buckets plus a partial one, and
# a pyramid of 64, 256, 1024, 4096. Every build goes to its own temporary
# cache_dir: system.file("extdata") is writable, so a default build would drop
# gram files into the installed package, and a shared directory would let one
# test's build decide what a later test opens.

# bucket reduction ------------------------------------------------------

test_that("gm_bucket_extrema returns each bucket's extrema and resolves a tie to the earliest sample", {
  set.seed(1)
  values <- rnorm(3522)
  samples <- seq_along(values) - 1L
  # 3522 = 55 * 64 + 2, so the last bucket is partial
  group <- samples %/% 64L

  extrema <- gm_bucket_extrema(values, samples, 64L)

  expect_equal(nrow(extrema), 56L)
  expect_equal(extrema$min, as.vector(tapply(values, group, min)))
  expect_equal(extrema$max, as.vector(tapply(values, group, max)))
  expect_equal(
    extrema$min_at,
    as.vector(tapply(samples, group, function(s) s[[1L]])) +
      as.vector(tapply(values, group, which.min)) -
      1L
  )
  expect_equal(
    extrema$max_at,
    as.vector(tapply(samples, group, function(s) s[[1L]])) +
      as.vector(tapply(values, group, which.max)) -
      1L
  )

  # padding repeats the last element, so this is also what proves the
  # partial-bucket padding cannot move an extremum onto a copied sample
  tied <- gm_bucket_extrema(c(2, 1, 1, 5, 5), 0:4, 4L)
  expect_equal(tied$min_at, c(1L, 4L))
  expect_equal(tied$max_at, c(3L, 4L))
})


# building --------------------------------------------------------------

test_that("build_overview writes a correct pyramid beside the record", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  expect_invisible(build_overview(cache))

  # the table and the manifest are published beside each other
  paths <- cache_paths(cache)
  expect_true(file.exists(paths[["manifest"]]))
  expect_true(file.exists(paths[["cache"]]))
  expect_equal(basename(paths[["cache"]]), "bard-egm.gram.parquet")
  expect_equal(dirname(paths[["cache"]]), dirname(paths[["manifest"]]))

  section <- 
    jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)$cache
  expect_equal(section$buckets, c(64, 256, 1024, 4096))
  expect_equal(section$channels, cache@channels)
  expect_equal(section$fingerprint, cache@fingerprint)

  overview <- nanoparquet::read_parquet(paths[["cache"]])
  expect_equal(as.vector(table(overview$level)), c(56L, 14L, 4L, 1L))
  expect_equal(ncol(overview), 2L + 4L * 14L)

  expect_output(print(cache), "overview:   4 levels (64..4096 samples), bard-egm.gram.parquet", fixed = TRUE)
  expect_message(build_overview(cache), "already built")

  # a merged level equals a direct reduction of the raw signal, so merging
  # upward never drifts from what a single pass would have found
  raw <- as.data.frame(read_viewport(
    cache,
    list(begin = 0, end = cache@n_samples),
    resolution = "raw"
  )$data)

  level2 <- overview[overview$level == 2L, ]
  direct <- gm_bucket_extrema(raw[["I"]], raw$sample, 256L)
  expect_equal(level2$start, seq(0L, by = 256L, length.out = 14L))
  expect_equal(level2$ch1.min, direct$min)
  expect_equal(level2$ch1.min_at, direct$min_at)
  expect_equal(level2$ch1.max, direct$max)
  expect_equal(level2$ch1.max_at, direct$max_at)

  top <- overview[overview$level == 4L, ]
  expect_equal(nrow(top), 1L)
  expect_equal(top$ch1.min, min(raw[["I"]]))
  expect_equal(top$ch1.max, max(raw[["I"]]))
})

test_that("the overview does not depend on chunk size or storage format", {
  # 1 s chunks are 960 samples, so the record is read in four pieces; 100 s
  # reads it in one
  chunked <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(chunked, chunk_seconds = 1)
  whole <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(whole, chunk_seconds = 100)
  rds <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(rds, format = "rds")

  # a chunk edge neither drops nor repeats a sample
  expect_equal(
    nanoparquet::read_parquet(cache_paths(chunked)[["cache"]]),
    nanoparquet::read_parquet(cache_paths(whole)[["cache"]])
  )

  # and the two formats hold the same table, written and read back
  expect_equal(basename(cache_paths(rds)[["cache"]]), "bard-egm.gram.rds")
  # nanoparquet returns a tbl and readRDS a bare data.frame, so compare the
  # values rather than the class the reader happened to put around them
  expect_equal(
    readRDS(cache_paths(rds)[["cache"]]),
    as.data.frame(nanoparquet::read_parquet(cache_paths(whole)[["cache"]]))
  )
  window <- list(begin = 0, end = 3522)
  expect_equal(
    read_viewport(rds, window, channels = c("I", "RV 1-2"), width_px = 100),
    read_viewport(whole, window, channels = c("I", "RV 1-2"), width_px = 100)
  )
})

test_that("VALIDATION level-1 buckets hold the exact raw extrema and their samples", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(cache)
  raw <- as.data.frame(read_viewport(
    cache,
    list(begin = 0, end = cache@n_samples),
    resolution = "raw"
  )$data)

  set.seed(2)
  for (bucket in c(0L, sample.int(54L, 5L), 55L)) {
    rows <- (bucket * 64L + 1L):min((bucket + 1L) * 64L, nrow(raw))
    window <- list(begin = bucket * 64L, end = min((bucket + 1L) * 64L, nrow(raw)))
    view <- read_viewport(cache, window, channels = "HIS D", width_px = 1, resolution = "overview")

    expect_equal(view$resolution, 64L)
    expect_equal(view$level, 1L)
    values <- raw[["HIS D"]][rows]
    expected <- data.frame(
      sample = raw$sample[rows][c(which.min(values), which.max(values))],
      value = c(min(values), max(values))
    )
    expected <- expected[order(expected$sample), ]
    expected <- expected[!duplicated(expected$sample), ]
    expect_equal(view$data[["HIS D"]]$sample, expected$sample)
    expect_equal(view$data[["HIS D"]]$value, expected$value)
  }
})

test_that("a rebuild replaces only the cache section of the manifest", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  dir.create(dirname(cache@manifest_path), recursive = TRUE)
  jsonlite::write_json(
    list(bookmarks = list(list(label = "retrograde A", begin = 300, end = 420))),
    cache@manifest_path,
    auto_unbox = TRUE,
    pretty = TRUE
  )

  build_overview(cache)
  manifest <- jsonlite::read_json(cache@manifest_path)

  expect_equal(manifest$bookmarks[[1L]]$label, "retrograde A")
  expect_equal(manifest$cache$version, 1L)
  expect_equal(manifest$record$stem, "bard-egm")
})


# viewport routing ------------------------------------------------------

test_that("the raw path returns exactly the requested samples at 977 Hz", {
  # EGM rounds elapsed seconds to nine digits, and at 977 Hz sample k sent as
  # k / rate lands on k + 1 for most k. At 1000 Hz the division is exact in
  # decimal and the trap never fires, so the bundled record is reopened with
  # its header claiming 977 Hz; the signal bytes are the same.
  dir <- tempfile("gram-record-")
  dir.create(dir)
  for (ext in c("hea", "dat", "qrs")) {
    file.copy(
      system.file("extdata", paste0("bard-egm.", ext), package = "gram"),
      file.path(dir, paste0("bard-egm.", ext))
    )
  }
  header <- file.path(dir, "bard-egm.hea")
  lines <- readLines(header)
  lines[[1L]] <- sub("^bard-egm 14 1000 ", "bard-egm 14 977 ", lines[[1L]])
  writeLines(lines, header)

  cache <- study_cache(file.path(dir, "bard-egm.hea"))
  expect_equal(cache@sample_rate, 977)

  # the trap is dense rather than sporadic, so a stratified sample catches it;
  # small and large k are both covered because the rounding error grows with
  # the magnitude of the elapsed seconds
  begins <- unique(c(
    0:20,
    as.integer(seq(21L, 3520L, length.out = 40L)),
    3521L
  ))
  for (begin in begins) {
    view <- read_viewport(cache, list(begin = begin, end = begin + 1L), resolution = "raw")
    expect_identical(view$data$sample, begin)
  }
})

test_that("read_viewport picks raw for a small window and a level for a large one", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(cache)

  # 2000 samples at 1000 px is under four per pixel
  raw <- read_viewport(cache, list(begin = 0, end = 2000), channels = "I", width_px = 1000)
  expect_equal(raw$resolution, "raw")
  expect_equal(raw$level, 0L)
  expect_equal(names(raw$data), c("sample", "I"))
  expect_equal(nrow(raw$data), 2000L)

  # the whole record at 100 px needs a bucket of at least 18, so level 1
  overview <- read_viewport(cache, list(begin = 0, end = 3522), width_px = 100)
  expect_equal(overview$resolution, 64L)
  expect_equal(overview$level, 1L)
  expect_named(overview$data, cache@channels)
  points <- vapply(overview$data, function(channel) length(channel$sample), integer(1))
  expect_true(all(points <= 4 * 100))
  expect_true(all(points > 56))

  # at 10 px a bucket must hold at least 2 * 3522 / 40 = 177 samples, so 256
  coarse <- read_viewport(cache, list(begin = 0, end = 3522), channels = "I", width_px = 10)
  expect_equal(coarse$resolution, 256L)
  expect_equal(coarse$level, 2L)

  # at 1 px nothing but the top level fits, and that is one bucket
  top <- read_viewport(cache, list(begin = 0, end = 3522), channels = "I", width_px = 1)
  expect_equal(top$resolution, 4096L)
  expect_equal(top$level, 4L)
  expect_length(top$data$I$sample, 2L)

  # a window inside one bucket, forced to the overview, uses the finest level
  forced <- read_viewport(cache, list(begin = 10, end = 20), channels = "I", width_px = 1000, resolution = "overview")
  expect_equal(forced$resolution, 64L)
  expect_true(all(forced$data$I$sample < 64))
})


# refusals --------------------------------------------------------------

test_that("build_overview refuses what it cannot honour", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )

  expect_error(build_overview(cache, chunk_seconds = 0), "`chunk_seconds` must be a single positive number", fixed = TRUE)
  expect_error(build_overview(cache, chunk_seconds = -1), "`chunk_seconds` must be a single positive number", fixed = TRUE)
  expect_error(build_overview(cache, format = "csv"), "'arg' should be one of")
})

test_that("read_viewport refuses a bad window, an unknown channel, and an unbuilt overview", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )

  expect_error(read_viewport(cache, list(begin = 0), width_px = 100), "`window` must be a list")
  expect_error(read_viewport(cache, list(begin = 0.5, end = 10), width_px = 100), "whole-number")
  expect_error(read_viewport(cache, list(begin = 10, end = 10), width_px = 100), "0 <= begin < end <= 3522")
  expect_error(read_viewport(cache, list(begin = 0, end = 4000), width_px = 100), "0 <= begin < end <= 3522")
  expect_error(read_viewport(cache, list(begin = 0, end = 100), channels = "nosuch", width_px = 100), "unknown channel")
  expect_error(read_viewport(cache, list(begin = 0, end = 100)), "`width_px` must be a single positive number")

  # a full-study window with nothing built must not fall back to reading the
  # whole raw signal
  expect_error(
    read_viewport(cache, list(begin = 0, end = 3522), width_px = 100),
    "overview not built or stale for this record; run build_overview()",
    fixed = TRUE
  )
})
