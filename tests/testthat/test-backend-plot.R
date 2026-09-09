test_that("gram_plot creates a widget carrying a backend's spec", {
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
  expect_named(widget$x, c("backend", "spec", "window", "extent"))

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
    vapply(widget$x$spec$panels, function(p) length(p$x), integer(1)),
    c(4L, 2L)
  )
  expect_equal(widget$x$window, list(min = 0, max = 3))
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

test_that("a backend that does not exist is refused at the prompt", {
  # the browser would throw too, but that error lands in a console the caller
  # may never open; match.arg names the choices where they typed the wrong one
  expect_error(
    gram_plot(list(list(x = 1:3, y = 1:3)), backend = "bogus"),
    "should be"
  )
})


# backends -------------------------------------------------------------

test_that("only the chosen backend's assets travel with the widget", {
  # the modularity claim, on the wire rather than in prose: a widget names its
  # backend and carries that backend's library and adapter and nothing else.
  # Core (the lifecycle) comes from the yaml and is not in this list.
  widget <- gram_plot(list(list(x = 1:3, y = 1:3)), backend = "uplot")
  carried <- vapply(widget$dependencies, function(d) d$name, character(1))

  expect_equal(carried, c("uplot", "gram-adapter-uplot"))
  expect_false("plotly-main" %in% carried)

  skip_if_not_installed("plotly")
  widget <- gram_plot(list(list(x = 1:3, y = 1:3)), backend = "plotly")
  carried <- vapply(widget$dependencies, function(d) d$name, character(1))

  expect_equal(carried, c("plotly-main", "gram-adapter-plotly"))
  expect_false("uplot" %in% carried)
})

test_that("a backend is a spec function and a dependency list", {
  backend <- gm_get_backend("uplot")

  expect_named(backend, c("spec", "dependencies"))
  expect_true(is.function(backend$spec))
  expect_true(all(vapply(
    backend$dependencies,
    function(d) inherits(d, "html_dependency"),
    logical(1)
  )))
  expect_error(gm_get_backend("bogus"), "should be")
})


# assets ---------------------------------------------------------------

test_that("the pinned uPlot and shared assets are installed", {
  lib <- system.file("htmlwidgets/lib", package = "gram")
  paths <- file.path(lib, c(
    "uplot/uPlot.iife.min.js", "uplot/uPlot.min.css", "uplot/LICENSE",
    "gram/gram-core.js", "gram/gram-core.css",
    "gram/gram-adapter-uplot.js", "gram/gram-uplot.css",
    "gram/gram-adapter-plotly.js"
  ))

  expect_true(all(file.exists(paths)))
  expect_true(all(file.info(paths)$size > 0))
})
