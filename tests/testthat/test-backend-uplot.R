# spec -----------------------------------------------------------------

test_that("the uPlot spec carries what R can decide and nothing else", {
  panels <- gm_validate_panels(list(
    list(label = "I", color = "#c00", x = 0:2, y = c(1, 3, 2)),
    list(label = "II", x = 0:2, y = c(2, 1, 3))
  ))

  spec <- gm_uplot_spec(
    panels,
    window = list(min = 0, max = 2),
    scale = list(kind = "elapsed", unit = "s"),
    panel_height = 150
  )

  expect_named(spec, c("panels", "x_axis_label", "x_is_time", "y_axis_size", "panel_height"))
  expect_length(spec$panels, 2L)
  expect_named(spec$panels[[1L]], c("label", "stroke", "x", "y"))
  expect_equal(vapply(spec$panels, `[[`, character(1), "label"), c("I", "II"))

  # a colour comes through as the stroke; a missing one falls back so the
  # adapter never has to guess
  expect_equal(vapply(spec$panels, `[[`, character(1), "stroke"), c("#c00", "#111"))
  expect_equal(spec$x_axis_label, "Time (s)")
  expect_false(spec$x_is_time)
  expect_equal(spec$panel_height, 150)
})

test_that("the x-axis label follows the scale kind", {
  panels <- gm_validate_panels(list(list(x = 1:3, y = 1:3)))
  spec_for <- function(kind) {
    gm_uplot_spec(panels, list(min = 1, max = 3), list(kind = kind), 120)
  }

  expect_equal(spec_for("index")$x_axis_label, "Sample")
  expect_equal(spec_for("elapsed")$x_axis_label, "Time (s)")
  expect_null(spec_for("timestamp")$x_axis_label)
  expect_true(spec_for("timestamp")$x_is_time)
})

test_that("a single-point panel survives as an array", {
  # a dead lead reduces to one point at a coarse tier; unwrapped it would reach
  # the browser as a scalar and uPlot would be handed a number where it wants
  # a series
  widget <- gram_plot(
    panels = list(list(label = "flat", x = 1, y = 0)),
    window = list(min = 0, max = 2)
  )

  expect_s3_class(widget$x$spec$panels[[1L]]$x, "AsIs")
  expect_true(grepl('"x":\\[1\\]', as.character(htmlwidgets:::toJSON(widget$x))))
})


# viewer ---------------------------------------------------------------

test_that("view_uplot loads every channel unless told otherwise", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  # the harness narrows channels by pushing fewer panels, so the opening widget
  # has to carry all of them or there is nothing to narrow from
  widget <- view_uplot(cache, list(begin = 0, end = 10))

  expect_equal(widget$x$backend, "uplot")
  expect_equal(
    vapply(widget$x$spec$panels, `[[`, character(1), "label"),
    cache@channels
  )
  expect_length(widget$x$spec$panels, length(cache@channels))
})

test_that("view_uplot adapts a raw window to panels", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))
  channels <- cache@channels[1:2]

  widget <- view_uplot(cache, list(begin = 0, end = 10), channels = channels)
  panels <- widget$x$spec$panels

  expect_s3_class(widget, "htmlwidget")
  expect_equal(widget$x$spec$x_axis_label, "Time (s)")
  expect_equal(vapply(panels, `[[`, character(1), "label"), channels)

  # a raw read has one sample column, so every panel shares its x
  expect_equal(as.double(panels[[1L]]$x), seq(0, 9) / cache@sample_rate)
  expect_equal(panels[[2L]]$x, panels[[1L]]$x)
  expect_equal(vapply(panels, function(panel) length(panel$x), integer(1)), c(10L, 10L))

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
