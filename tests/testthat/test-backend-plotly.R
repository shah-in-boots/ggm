skip_if_not_installed("plotly")

# spec -----------------------------------------------------------------

test_that("the plotly spec is the whole figure", {
  # two panels of different length, because that is what an overview tier
  # produces and what a shared-x layout has to accept
  panels <- gm_validate_panels(list(
    list(label = "I", color = "#c00", x = c(0, 1, 2, 3), y = c(0, 1, 0, 1)),
    list(label = "II", x = c(0.5, 2.5), y = c(1, 0))
  ))

  spec <- gm_plotly_spec(
    panels,
    window = list(min = 0, max = 3),
    scale = list(kind = "elapsed", unit = "s"),
    panel_height = 120
  )

  expect_named(spec, c("data", "layout", "config"))

  # one trace per panel, all on the one x axis, each on its own y axis
  expect_length(spec$data, 2L)
  expect_true(all(vapply(spec$data, function(t) t$type == "scattergl", logical(1))))
  expect_true(all(vapply(spec$data, function(t) t$xaxis == "x", logical(1))))
  expect_equal(vapply(spec$data, `[[`, character(1), "yaxis"), c("y", "y2"))
  expect_equal(spec$data[[1L]]$line$color, "#c00")
  expect_equal(spec$data[[2L]]$line$color, "#111")
  expect_length(spec$data[[2L]]$x, 2L)

  # the window is the forced range; the rows are the panels; every y is fixed
  # so a drag zooms x only
  expect_equal(spec$layout$grid$rows, 2L)
  expect_equal(spec$layout$grid$pattern, "coupled")
  expect_equal(spec$layout$xaxis$range, c(0, 3))
  expect_equal(spec$layout$xaxis$title$text, "Time (s)")
  expect_equal(spec$layout$height, 2 * 120 + 40)
  expect_true(spec$layout$yaxis$fixedrange)
  expect_true(spec$layout$yaxis2$fixedrange)
  expect_equal(spec$layout$yaxis$title$text, "I")
  expect_equal(spec$layout$yaxis2$title$text, "II")

  # nothing uPlot does not have
  expect_false(spec$config$displayModeBar)
  expect_false(spec$config$doubleClick)
  expect_false(spec$config$scrollZoom)
  expect_false(spec$config$showAxisDragHandles)
})

test_that("the borrowed plotly bundle is where the dependency says", {
  widget <- gram_plot(list(list(x = 1:3, y = 1:3)), backend = "plotly")
  main <- widget$dependencies[[1L]]

  expect_equal(main$name, "plotly-main")
  expect_true(file.exists(file.path(
    system.file(main$src$file, package = main$package), main$script
  )))
})


# viewer ---------------------------------------------------------------

test_that("one window drawn through two backends is the same window", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))
  window <- list(begin = 0, end = 10)
  channels <- cache@channels[1:2]

  p <- view_plotly(cache, window, channels = channels)
  u <- view_uplot(cache, window, channels = channels)

  expect_equal(p$x$backend, "plotly")
  expect_equal(u$x$backend, "uplot")
  expect_equal(p$x$window, u$x$window)
  expect_equal(p$x$extent, u$x$extent)

  # the same samples, shaped for each library
  expect_equal(as.double(p$x$spec$data[[1L]]$x), as.double(u$x$spec$panels[[1L]]$x))
  expect_equal(as.double(p$x$spec$data[[1L]]$y), as.double(u$x$spec$panels[[1L]]$y))
  expect_equal(p$x$spec$layout$yaxis$title$text, u$x$spec$panels[[1L]]$label)
})
