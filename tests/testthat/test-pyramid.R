# M0: build the pyramid on a throwaway copy of the bundled record, then exercise
# the router both ways (tier read vs raw fall-through).

test_that("build_pyramid writes the sidecar and a round-tripping manifest", {
  skip_if_not_installed("EGM")
  skip_if_not_installed("arrow")
  dir <- local_bard_dir()
  study <- open_study("bard-egm", dir)
  expect_null(study$pyramid) # nothing built yet

  path <- suppressMessages(build_pyramid(study, tiers = c(10, 100)))
  expect_true(dir.exists(path))
  expect_true(file.exists(file.path(path, "manifest.json")))
  expect_true(file.exists(file.path(
    path, "signal", "channel=11", "tier=10", "part.parquet"
  ))) # HIS D is channel 11

  m <- read_manifest(file.path(path, "manifest.json"))
  expect_equal(m$sampling_frequency, 1000)
  expect_equal(m$n_samples, 3522)
  expect_identical(m$tiers$samples_per_bucket, c(10L, 100L))
  expect_equal(nrow(m$channels), 14L)
})

test_that("open_study binds an existing pyramid", {
  skip_if_not_installed("EGM")
  skip_if_not_installed("arrow")
  dir <- local_bard_dir()
  suppressMessages(build_pyramid(open_study("bard-egm", dir), tiers = c(10, 100)))

  study <- open_study("bard-egm", dir)
  expect_false(is.null(study$pyramid))
  expect_identical(study$pyramid$manifest$tiers$samples_per_bucket, c(10L, 100L))
  expect_output(print(study), "pyramid: 2 tiers")
})

test_that(".select_tier picks the coarsest adequate tier, else raw", {
  pyramid <- list(manifest = list(tiers = data.frame(
    samples_per_bucket = c(10L, 100L),
    use_when_ppp_above = c(10L, 100L)
  )))
  expect_identical(.select_tier(5, pyramid), "raw") # below finest tier
  expect_identical(.select_tier(50, pyramid), 10L) # only tier 10 eligible
  expect_identical(.select_tier(200, pyramid), 100L) # coarsest eligible
  expect_identical(.select_tier(200, pyramid, units = "digital"), "raw") # pyramid is physical
  expect_identical(.select_tier(NA_real_, pyramid), "raw") # unknown viewport
  expect_identical(.select_tier(200, NULL), "raw") # no pyramid
})

test_that("get_window serves a tier when zoomed out, raw when zoomed in", {
  skip_if_not_installed("EGM")
  skip_if_not_installed("arrow")
  dir <- local_bard_dir()
  suppressMessages(build_pyramid(open_study("bard-egm", dir), tiers = c(10, 100)))
  study <- open_study("bard-egm", dir)

  # Full study across a narrow viewport -> high ppp -> coarse tier.
  wide <- get_window(study, channels = "HIS D", begin = 0, end = 3.522, px_width = 20)
  expect_identical(attr(wide, "tier"), 100L)
  expect_lt(nrow(wide), 3522L) # downsampled

  # Same window across a wide viewport -> low ppp -> raw.
  zoomed <- get_window(study, channels = "HIS D", begin = 0, end = 3.522, px_width = 5000)
  expect_identical(attr(zoomed, "tier"), "raw")
  expect_identical(nrow(zoomed), 3522L)
})

test_that("tier values are exact raw samples (LTTB selects real points)", {
  skip_if_not_installed("EGM")
  skip_if_not_installed("arrow")
  dir <- local_bard_dir()
  suppressMessages(build_pyramid(open_study("bard-egm", dir), tiers = c(10, 100)))
  study <- open_study("bard-egm", dir)

  tier <- get_window(study, channels = "HIS D", begin = 0, end = 3.522, px_width = 20)
  raw <- get_window(study, channels = "HIS D", begin = 0, end = 3.522, px_width = 5000)

  # every tier point is a real sample, and time is its exact companion
  expect_true(all(tier$sample %in% raw$sample))
  expect_equal(tier$time, tier$sample / 1000)
  # the value at each selected sample matches the full-resolution value
  matched <- raw[match(tier$sample, raw$sample), ]
  expect_equal(tier[["HIS D"]], matched[["HIS D"]])
})

test_that("build_pyramid refuses to clobber without overwrite", {
  skip_if_not_installed("EGM")
  skip_if_not_installed("arrow")
  dir <- local_bard_dir()
  study <- open_study("bard-egm", dir)
  suppressMessages(build_pyramid(study, tiers = c(10, 100)))
  expect_error(build_pyramid(study, tiers = c(10, 100)), "already exists")
  expect_invisible(suppressMessages(build_pyramid(study, tiers = c(10, 100), overwrite = TRUE)))
})
