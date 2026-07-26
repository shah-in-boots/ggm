test_that("view_uplot adapts a raw window to uPlot columns", {
  record <- file.path(system.file("extdata", package = "ggm"), "bard-egm.dat")
  cache <- study_cache(record, cache_dir = tempdir())
  channels <- cache@channels[1:2]

  widget <- view_uplot(
    cache,
    begin = "00:00:00",
    interval = "10 ms",
    channels = channels
  )

  expect_s3_class(widget, "htmlwidget")
  expect_equal(widget$x$scale, list(kind = "elapsed", unit = "s"))
  expect_equal(vapply(widget$x$series, `[[`, character(1), "label"), channels)
  expect_false(any(vapply(
    widget$x$series,
    function(x) "color" %in% names(x),
    logical(1)
  )))
  expect_equal(widget$x$columns[[1L]], seq(0, 9) / cache@sample_rate)
  expect_equal(vapply(widget$x$columns, length, integer(1)), rep(10L, 3L))
})
