test_that("gram_plot creates a uPlot htmlwidget", {
  widget <- gram_plot(
    panels = list(
      list(label = "I", x = 0:2, y = c(1, 3, 2)),
      list(label = "II", x = 0:2, y = c(2, 1, 3))
    ),
    scale = list(kind = "elapsed", unit = "s")
  )

  expect_s3_class(widget, "htmlwidget")
  expect_s3_class(widget, "gram_plot")
  expect_equal(widget$x$backend, "uplot")
  expect_equal(widget$x$scale$kind, "elapsed")
  expect_equal(widget$x$layout, list(panel_height = 120))
  expect_length(widget$x$panels, 2L)
  expect_equal(
    vapply(widget$x$panels, `[[`, character(1), "label"),
    c("I", "II")
  )
  expect_equal(vapply(widget$x$panels, function(p) length(p$x), integer(1)), c(3L, 3L))
  expect_equal(vapply(widget$x$panels, function(p) length(p$y), integer(1)), c(3L, 3L))

  # the drawn range is the panels' own when the caller does not say otherwise,
  # and the record is assumed to be no wider than what was handed over
  expect_equal(widget$x$window, list(min = 0, max = 2))
  expect_equal(widget$x$extent, widget$x$window)
})

test_that("panels may differ in length", {
  # this is the whole reason panels replaced aligned columns: an overview tier
  # reports each channel's extrema at the samples they fell on, so a channel
  # whose signal is busier contributes more points than a quiet one
  widget <- gram_plot(
    panels = list(
      list(label = "I", x = c(0, 1, 2, 3), y = c(0, 1, 0, 1)),
      list(label = "II", x = c(0.5, 2.5), y = c(1, 0))
    )
  )

  expect_equal(
    vapply(widget$x$panels, function(p) length(p$x), integer(1)),
    c(4L, 2L)
  )
  expect_equal(widget$x$window, list(min = 0, max = 3))
})

test_that("a single-point panel survives as an array", {
  # a dead lead reduces to one point at a coarse tier; unwrapped it would reach
  # the browser as a scalar and uPlot would be handed a number where it wants
  # a series
  widget <- gram_plot(
    panels = list(list(label = "flat", x = 1, y = 0)),
    window = list(min = 0, max = 2)
  )

  expect_s3_class(widget$x$panels[[1L]]$x, "AsIs")
  expect_true(grepl('"x":\\[1\\]', as.character(htmlwidgets:::toJSON(widget$x))))
})

test_that("gram_plot rejects panels a renderer cannot draw", {
  expect_error(gram_plot(list()), "at least one panel")
  expect_error(gram_plot(list(list(x = 1:3))), "must hold `x` and `y`")
  expect_error(gram_plot(list(list(x = 1:3, y = 1:2))), "equal length")
  expect_error(gram_plot(list(list(x = numeric(0), y = numeric(0)))), "cannot be empty")
  expect_error(
    gram_plot(list(list(x = c(1, 3, 2), y = 1:3))),
    "in increasing order"
  )
  expect_error(
    gram_plot(list(list(x = 1:3, y = 1:3)), window = list(min = 2, max = 1)),
    "min < max"
  )
  expect_error(
    gram_plot(list(list(x = 1:3, y = 1:3)), scale = list(kind = "time")),
    "timestamp"
  )
  expect_error(
    gram_plot(list(list(x = 1:3, y = 1:3)), panel_height = 40),
    "at least 80"
  )
})


test_that("the pinned uPlot and stacked-panel assets are installed", {
  uplotAssets <- c("uPlot.iife.min.js", "uPlot.min.css", "LICENSE")
  paths <- c(
    file.path(
      system.file("htmlwidgets/lib/uplot", package = "gram"),
      uplotAssets
    ),
    system.file("htmlwidgets/lib/gram/gram-uplot.css", package = "gram")
  )

  expect_true(all(file.exists(paths)))
  expect_true(all(file.info(paths)$size > 0))
})
