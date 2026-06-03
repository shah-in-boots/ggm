test_that("open_study reads header metadata from the bundled record", {
  study <- open_test_study()

  expect_true(is_study(study))
  expect_identical(study$record, "bard-egm")
  expect_equal(study$frequency, 1000)
  expect_identical(study$n_samples, 3522L)
  expect_length(study$channels, 14L)
  expect_true(all(c("HIS D", "RV 1-2") %in% study$channels))
  # duration = n_samples / frequency
  expect_equal(study$duration, 3.522)
})

test_that("is_study discriminates", {
  expect_false(is_study(list()))
  expect_false(is_study(NULL))
})

test_that("open_study fails clearly on a missing record", {
  expect_error(
    open_study("does-not-exist", test_record_dir()),
    "No header found"
  )
  expect_error(open_study("bard-egm", "/no/such/dir"), "does not exist")
  expect_error(open_study(c("a", "b"), test_record_dir()), "single non-empty")
})

test_that("print.ggm_study is informative and returns invisibly", {
  study <- open_test_study()
  expect_output(print(study), "ggm_study")
  expect_output(print(study), "14 channels")
  expect_invisible(print(study))
})
