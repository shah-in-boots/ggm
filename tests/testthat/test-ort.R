# Real-record smoke test against the large ORT study (downloaded once via
# piggyback to the user cache; see helper-ggm.R). Skips cleanly when EGM /
# piggyback are unavailable or offline, and never builds the pyramid here
# (that is a multi-minute operation validated manually, not in CI).

test_that("a windowed raw read on the real ORT study honours the contract", {
  # Real skips (no EGM / offline) propagate; a failed download (e.g. the data
  # release isn't published yet) becomes a skip rather than a test failure.
  study <- tryCatch(
    suppressWarnings(open_ort_study()),
    error = function(e) skip(paste("ORT data unavailable:", conditionMessage(e)))
  )

  expect_true(is_study(study))
  expect_gt(study$duration, 3600) # multi-hour
  fs <- study$frequency

  # A 2 s window, zoomed in -> raw .dat range read.
  w <- get_window(study, channels = study$channels[1], begin = 100, end = 102, px_width = 4000)
  expect_identical(attr(w, "tier"), "raw")
  expect_identical(nrow(w), as.integer(2 * fs))
  expect_equal(range(w$sample), c(100, 102) * fs)
  expect_equal(w$time, w$sample / fs)
})
