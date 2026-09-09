test_that("an overview tier becomes panels of differing length", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(cache)

  # 3522 samples clears 4 * width_px at any ordinary panel width, so `auto`
  # would read raw; the overview path has to be asked for
  window <- list(begin = 1000, end = 2000)
  view <- gm_read_panels(cache, window, width_px = 100)

  expect_equal(view$resolution, 64L)
  expect_equal(view$level, 1L)
  expect_length(view$panels, length(cache@channels))

  # Every channel puts its points at its own samples. This is what aligned
  # columns cannot express and why panels carry their own x. On a busier
  # record the lengths differ too, because a flat bucket collapses its pair to
  # one point; every channel here is active enough to contribute two per
  # bucket, so the positions are what separates them.
  xs <- lapply(view$panels, function(panel) as.double(panel$x))
  expect_length(unique(xs), length(cache@channels))

  for (panel in view$panels) {
    expect_true(all(is.finite(panel$x)))
    expect_false(is.unsorted(panel$x, strictly = TRUE))
    expect_equal(length(panel$x), length(panel$y))
  }

  # a bucket straddling the window edge is returned whole, so points reach past
  # the window; the renderer is given the window explicitly and clips to it
  expect_lt(min(unlist(xs)), view$window$min)
  expect_gt(max(unlist(xs)), view$window$max)
  expect_equal(view$window, list(min = 1, max = 2))

  # the payload survives validation, which is what a push runs on the way out
  expect_silent(gm_validate_panels(view$panels))
})
