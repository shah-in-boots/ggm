test_that("view_uplot loads every channel unless told otherwise", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  # the viewer's own channel list switches channels off client-side, so the
  # payload has to carry all of them or they cannot be switched back on
  widget <- view_uplot(cache, list(begin = 0, end = 10))

  expect_equal(
    vapply(widget$x$panels, `[[`, character(1), "label"),
    cache@channels
  )
  expect_length(widget$x$panels, length(cache@channels))
})

test_that("view_uplot adapts a raw window to panels", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))
  channels <- cache@channels[1:2]

  widget <- view_uplot(
    cache,
    window = list(begin = 0, end = 3000),
    channels = channels
  )

  expect_s3_class(widget, "htmlwidget")
  expect_equal(widget$x$scale, list(kind = "elapsed", unit = "s"))
  expect_equal(vapply(widget$x$panels, `[[`, character(1), "label"), channels)
  expect_false(any(vapply(
    widget$x$panels,
    function(panel) "color" %in% names(panel),
    logical(1)
  )))

  # a raw read has one sample column, so every panel shares its x
  expect_equal(
    as.double(widget$x$panels[[1L]]$x),
    seq(0, 9) / cache@sample_rate
  )
  expect_equal(widget$x$panels[[2L]]$x, widget$x$panels[[1L]]$x)
  expect_equal(
    vapply(widget$x$panels, function(panel) length(panel$x), integer(1)),
    c(10L, 10L)
  )

  # the record is wider than the window, and panning is clamped to the record
  expect_equal(widget$x$window, list(min = 0, max = 10 / cache@sample_rate))
  expect_equal(
    widget$x$extent,
    list(min = 0, max = cache@n_samples / cache@sample_rate)
  )
})

test_that("view_uplot opens on the whole record", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  # at a coarse tier the whole record is the study navigator, so that is what a
  # reader should be shown first rather than an arbitrary opening slice
  widget <- view_uplot(cache, channels = cache@channels[1])

  expect_equal(widget$x$window, widget$x$extent)
  expect_equal(
    widget$x$window,
    list(min = 0, max = cache@n_samples / cache@sample_rate)
  )
})

test_that("an overview tier becomes panels of differing length", {
  cache <- study_cache(
    system.file("extdata", "bard-egm.hea", package = "gram"),
    cache_dir = tempfile("gram-cache-")
  )
  build_overview(cache)

  # 3522 samples clears 4 * width_px at any ordinary panel width, so `auto`
  # would read raw; the overview path has to be asked for
  window <- list(begin = 1000, end = 2000)
  view <- gm_viewport_panels(cache, window, width_px = 100)

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
