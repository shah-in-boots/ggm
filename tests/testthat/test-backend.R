test_that("gram_plot creates a uPlot htmlwidget", {
  widget <- gram_plot(
    columns = list(0:2, c(1, 3, 2), c(2, 1, 3)),
    scale = list(kind = "elapsed", unit = "s"),
    series = list(list(label = "I"), list(label = "II"))
  )

  expect_s3_class(widget, "htmlwidget")
  expect_s3_class(widget, "gram_plot")
  expect_equal(widget$x$backend, "uplot")
  expect_equal(widget$x$scale$kind, "elapsed")
  expect_equal(widget$x$layout, list(panel_height = 120))
  expect_equal(vapply(widget$x$columns, length, integer(1)), rep(3L, 3L))
})

test_that("gram_plot rejects data that uPlot cannot align", {
  expect_error(gram_plot(list(1:3)), "at least one signal")
  expect_error(gram_plot(list(1:3, 1:2)), "equal length")
  expect_error(gram_plot(list(c(1, 3, 2), 1:3)), "in increasing order")
  expect_error(
    gram_plot(list(1:3, 1:3), series = list(list(), list())),
    "one list per signal"
  )
  expect_error(
    gram_plot(list(1:3, 1:3), scale = list(kind = "time")),
    "timestamp"
  )
  expect_error(gram_plot(list(1:3, 1:3), panel_height = 40), "at least 80")
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
