# LTTB downsampling properties. Pure, no EGM/arrow needed.

test_that("lttb_reduce keeps endpoints and hits the target point count", {
  s <- 0:999
  v <- sin(s / 50)
  red <- lttb_reduce(s, v, threshold = 100, envelope = FALSE)

  expect_identical(nrow(red), 100L)
  expect_identical(red$sample[1], 0L)
  expect_identical(red$sample[nrow(red)], 999L)
  # samples stay in order and within range
  expect_false(is.unsorted(red$sample))
  expect_true(all(red$sample %in% s))
})

test_that("lttb_reduce preserves a sharp spike", {
  s <- 0:999
  v <- rep(0, 1000)
  v[500] <- 100 # a single, sharp deflection
  red <- lttb_reduce(s, v, threshold = 50, envelope = TRUE)

  # the spike sample survives downsampling (that is the whole point of LTTB)
  expect_true(499L %in% red$sample)
  # and the envelope brackets it somewhere
  expect_equal(max(red$vmax), 100)
})

test_that("lttb_reduce is a no-op when threshold >= n", {
  s <- 0:9
  v <- runif(10)
  red <- lttb_reduce(s, v, threshold = 100, envelope = TRUE)
  expect_identical(red$sample, s)
  expect_identical(red$value, v)
  expect_identical(red$vmin, v)
})

test_that("envelope columns appear only when requested", {
  red_on <- lttb_reduce(0:999, rnorm(1000), 100, envelope = TRUE)
  red_off <- lttb_reduce(0:999, rnorm(1000), 100, envelope = FALSE)
  expect_true(all(c("vmin", "vmax") %in% names(red_on)))
  expect_identical(names(red_off), c("sample", "value"))
})
