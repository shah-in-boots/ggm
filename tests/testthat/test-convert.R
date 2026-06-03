# The sample <-> time boundary (D-8). Pure, no EGM needed.

test_that("time_to_sample converts and rounds to the nearest sample", {
  expect_identical(time_to_sample(c(0, 1, 1.5), frequency = 1000), c(0L, 1000L, 1500L))
  # 1.2345 s @ 1000 Hz -> 1234.5 -> rounds to 1234 (round-half-to-even on .5 is
  # avoided here; this is a plain non-half value)
  expect_identical(time_to_sample(1.2344, frequency = 1000), 1234L)
})

test_that("sample_to_time is exact", {
  expect_identical(sample_to_time(c(0L, 1000L, 1500L), frequency = 1000), c(0, 1, 1.5))
})

test_that("a valid sample index round-trips exactly", {
  samples <- c(0L, 1L, 999L, 3521L)
  expect_identical(time_to_sample(sample_to_time(samples, 1000), 1000), samples)
})

test_that("frequency is validated at the boundary", {
  expect_error(time_to_sample(1, frequency = 0), "positive")
  expect_error(time_to_sample(1, frequency = -5), "positive")
  expect_error(sample_to_time(1L, frequency = c(1000, 500)), "single")
  expect_error(sample_to_time(1L, frequency = NA_real_), "positive")
})

test_that("inputs must be numeric", {
  expect_error(time_to_sample("1", frequency = 1000), "numeric")
  expect_error(sample_to_time("1", frequency = 1000), "numeric")
})
