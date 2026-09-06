# verbs -----------------------------------------------------------------

test_that("channel indices below one are refused rather than sent", {
  # a 0-based index arriving from the browser would silently draw the wrong
  # lead, so the verb refuses before gm_send() ever reaches a session
  proxy <- structure(list(id = "x", session = NULL), class = "gm_proxy")

  expect_error(gm_set_visible(proxy, c(0, 1)), "1-based channel indices")
  expect_error(gm_set_visible(proxy, c(1, NA)), "1-based channel indices")
  expect_error(gm_set_visible(proxy, "I"), "1-based channel indices")
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
