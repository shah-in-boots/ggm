test_that("get_window returns the documented sample + time contract", {
  study <- open_test_study()
  w <- get_window(study, channels = c("HIS D", "RV 1-2"), begin = 1, end = 2)

  expect_s3_class(w, "ggm_window")
  expect_s3_class(w, "data.table")
  # sample + time + the two requested channels, in that order
  expect_identical(names(w), c("sample", "time", "HIS D", "RV 1-2"))

  # begin=1, end=2 @ 1000 Hz -> samples 1000..1999 (1000 rows)
  expect_identical(nrow(w), 1000L)
  expect_identical(range(w$sample), c(1000L, 1999L))

  # time is the exact companion of sample
  expect_equal(w$time, w$sample / 1000)
  expect_equal(range(w$time), c(1, 1.999))
})

test_that("spine always serves the raw tier", {
  study <- open_test_study()
  w <- get_window(study, begin = 0, end = 0.5)
  expect_identical(attr(w, "tier"), "raw")
  expect_identical(attr(w, "frequency"), 1000)
})

test_that("NULL channels reads every channel", {
  study <- open_test_study()
  w <- get_window(study, begin = 0, end = 0.1)
  # sample + time + all 14 channels
  expect_identical(ncol(w), 16L)
  expect_true(all(study$channels %in% names(w)))
})

test_that("px_width drives points-per-pixel, not the data", {
  study <- open_test_study()
  # window of 1 s @ 1000 Hz = 1000 samples across 500 px -> ppp = 2
  w <- get_window(study, begin = 0, end = 1, px_width = 500)
  expect_equal(attr(w, "ppp"), 2)
  # without px_width, ppp is unknown
  w2 <- get_window(study, begin = 0, end = 1)
  expect_true(is.na(attr(w2, "ppp")))
})

test_that("get_window validates its inputs", {
  study <- open_test_study()
  expect_error(get_window(study, channels = "NOPE"), "Unknown channel")
  expect_error(get_window(study, begin = 2, end = 1), "greater than")
  expect_error(get_window(list()), "ggm_study")
})

test_that("not-yet-built accessors fail loudly with their milestone", {
  study <- open_test_study()
  expect_error(get_overview(study), class = "ggm_not_implemented")
  expect_error(get_annotations(study), class = "ggm_not_implemented")
  expect_error(get_overview(study), "M2.5")
})
