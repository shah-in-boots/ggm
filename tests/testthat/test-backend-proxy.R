# verbs -----------------------------------------------------------------

test_that("a push carries a spec built by the named backend", {
  # the same translation a first render runs, sent into a live widget; the
  # session is faked so the message can be read back instead of delivered
  captured <- NULL
  proxy <- structure(
    list(
      id = "viewer",
      session = list(sendCustomMessage = function(type, message) {
        captured <<- list(type = type, message = message)
      })
    ),
    class = "gm_proxy"
  )

  gm_set_data(
    proxy,
    panels = list(list(label = "I", x = 0:2, y = c(1, 3, 2))),
    window = list(min = 0, max = 2),
    backend = "uplot",
    scale = list(kind = "elapsed", unit = "s")
  )

  expect_equal(captured$type, "gram:set_data")
  expect_named(captured$message, c("id", "spec", "window"))
  expect_equal(captured$message$id, "viewer")
  expect_equal(captured$message$window, list(min = 0, max = 2))
  expect_equal(captured$message$spec$x_axis_label, "Time (s)")
  expect_length(captured$message$spec$panels, 1L)
})

test_that("a push for plotly carries the figure", {
  skip_if_not_installed("plotly")
  captured <- NULL
  proxy <- structure(
    list(
      id = "viewer",
      session = list(sendCustomMessage = function(type, message) {
        captured <<- list(type = type, message = message)
      })
    ),
    class = "gm_proxy"
  )

  gm_set_data(
    proxy,
    panels = list(list(label = "I", x = 0:2, y = c(1, 3, 2))),
    window = list(min = 0, max = 2),
    backend = "plotly"
  )

  expect_named(captured$message$spec, c("data", "layout", "config"))
  expect_equal(captured$message$spec$layout$xaxis$range, c(0, 2))
  expect_equal(captured$message$spec$layout$grid$rows, 1L)
})

test_that("a push refuses what a first render would refuse", {
  proxy <- structure(list(id = "x", session = NULL), class = "gm_proxy")

  expect_error(gm_set_data(proxy, list(), list(min = 0, max = 1)), "at least one panel")
  expect_error(
    gm_set_data(proxy, list(list(x = 1:3, y = 1:3)), list(min = 2, max = 1)),
    "min < max"
  )
  expect_error(
    gm_set_data(proxy, list(list(x = 1:3, y = 1:3)), list(min = 0, max = 1), backend = "bogus"),
    "should be"
  )
})


# selection ------------------------------------------------------------

test_that("a viewer selection becomes a canonical sample range", {
  # 1000 Hz, 3522 samples
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  expect_equal(
    normalize_selection(cache, list(xmin = 0.1, xmax = 0.2)),
    list(begin = 100, end = 200)
  )

  # a right-to-left drag selects the same samples as a left-to-right one
  expect_equal(
    normalize_selection(cache, list(xmin = 0.2, xmax = 0.1)),
    normalize_selection(cache, list(xmin = 0.1, xmax = 0.2))
  )

  # uPlot reports domain units, which run past the data when the user drags
  # off the end of the panel
  expect_equal(
    normalize_selection(cache, list(xmin = -5, xmax = 99)),
    list(begin = 0, end = 3522)
  )
})

test_that("a selection that holds no samples is not a selection", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  # nothing selected yet, and a plain click that the browser let through:
  # both leave the caller's current window standing
  expect_null(normalize_selection(cache, NULL))
  expect_null(normalize_selection(cache, list(xmin = 0.1, xmax = 0.1)))
  expect_null(normalize_selection(cache, list(xmin = -9, xmax = -8)))
})

test_that("a malformed selection is refused rather than guessed at", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))

  expect_error(normalize_selection(cache, list(xmin = 0.1)), "`xmin` and `xmax`")
  expect_error(normalize_selection(cache, 0.1), "`xmin` and `xmax`")
  expect_error(
    normalize_selection(cache, list(xmin = NA, xmax = 0.2)),
    "two finite seconds"
  )
  expect_error(
    normalize_selection(cache, list(xmin = NULL, xmax = 0.2)),
    "two finite seconds"
  )
})
