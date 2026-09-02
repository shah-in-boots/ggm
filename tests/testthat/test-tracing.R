test_that("tracing reads a window and starts with an empty script", {
  x <- tracing(
    study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  )

  expect_equal(x@channels, c("HIS D", "RV 1-2"))
  expect_equal(length(x@samples), 500L)
  expect_equal(x@samples[[1L]], 0)
  expect_equal(lengths(x@values), c("HIS D" = 500L, "RV 1-2" = 500L))
  expect_length(x@ops, 0L)
})

test_that("long windows decimate to max_points with a warning", {
  expect_warning(
    x <- tracing(
      study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
      begin = "00:00:00",
      interval = "2 s",
      channels = "HIS D",
      max_points = 300
    ),
    "decimated"
  )
  expect_lte(length(x@samples), 301L)
  expect_equal(x@samples[[1L]], 0)
})

test_that("verbs append operations in script order", {
  x <- tracing(
    study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  ) |>
    reveal() |>
    add_arrow(
      from = at(100, "RV 1-2"),
      to = at(200, "HIS D"),
      label = "VA"
    ) |>
    emphasize(at(200, "HIS D"))

  expect_equal(vapply(x@ops, `[[`, character(1), "type"),
               c("reveal", "arrow", "emphasize"))
  expect_equal(x@ops[[2L]]$label, "VA")
})

test_that("references outside the tracing fail clearly", {
  x <- tracing(
    study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  )

  expect_error(
    emphasize(x, at(100, "CS 1-2")),
    "not in this tracing"
  )
  expect_error(
    emphasize(x, at(99999, "HIS D")),
    "outside this tracing's window"
  )
  expect_error(emphasize(x, 100), "must be a point from at\\(\\)")
})

test_that("tracing_spec compiles one lane per channel and one op per verb", {
  spec <- tracing(
    study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  ) |>
    reveal() |>
    add_arrow(from = at(100, "RV 1-2"), to = at(200, "HIS D"), label = "VA") |>
    tracing_spec()

  expect_equal(spec$version, 1L)
  expect_equal(spec$height, 240)
  expect_equal(vapply(spec$ops, `[[`, character(1), "type"),
               c("reveal", "arrow"))

  expect_equal(lengths(regmatches(
    spec$svg, gregexpr('class="gram-trace"', spec$svg, fixed = TRUE)
  ))[[1L]], 2L)
  expect_match(spec$svg, 'id="gram-arrow-1"', fixed = TRUE)
  expect_match(spec$svg, ">VA</text>", fixed = TRUE)
  expect_match(spec$svg, "viewBox=\"0 0 1000 240\"", fixed = TRUE)
})

test_that("channel labels are escaped into the markup", {
  x <- tracing(
    study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  )
  spec <- tracing_spec(add_arrow(
    x,
    from = at(100, "RV 1-2"),
    to = at(200, "HIS D"),
    label = '<script>&"'
  ))

  expect_match(spec$svg, "&lt;script&gt;&amp;&quot;", fixed = TRUE)
  expect_false(grepl("<script>", spec$svg, fixed = TRUE))
})

test_that("an arrow crossing lanes lands on both baselines", {
  x <- tracing(
    study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  )
  geom <- gram:::gm_tracing_geometry(x)

  expect_equal(gram:::gm_geom_baseline(x, "HIS D"), 60)
  expect_equal(gram:::gm_geom_baseline(x, "RV 1-2"), 180)
  expect_equal(gram:::gm_geom_x(geom, x@samples[[1L]]), 0)
  expect_equal(gram:::gm_geom_x(geom, x@samples[[length(x@samples)]]), 1000)
})


# refusals --------------------------------------------------------------

test_that("at() refuses a reference that is not one finite point", {
  expect_error(at(NA, "HIS D"), "single finite number")
  expect_error(at(Inf, "HIS D"), "single finite number")
  expect_error(at(c(1, 2), "HIS D"), "single finite number")
  expect_error(at("100", "HIS D"), "single finite number")
  expect_error(at(numeric(), "HIS D"), "single finite number")

  expect_error(at(100, c("HIS D", "RV 1-2")), "single channel label")
  expect_error(at(100, 1), "single channel label")
})

test_that("tracing refuses a max_points that cannot describe a window", {
  expect_error(
    tracing(
      study_cache(system.file("extdata", "bard-egm.hea", package = "gram")),
      begin = "00:00:00",
      interval = "100 ms",
      channels = "HIS D",
      max_points = 1
    ),
    "must be at least 2"
  )
})

test_that("the verbs refuse anything that is not a tracing", {
  expect_error(reveal(list()), "S7_inherits")
  expect_error(add_arrow(list(), at(1, "I"), at(2, "I")), "S7_inherits")
  expect_error(emphasize(list(), at(1, "I")), "S7_inherits")
  expect_error(tracing_spec(list()), "S7_inherits")
})

test_that("a Tracing cannot hold values that disagree with its channels", {
  expect_error(
    gram:::Tracing(
      stem = "x", sample_rate = 1000, samples = c(1, 2),
      channels = character(), values = list(),
      units = "physical", ops = list()
    ),
    "at least one channel"
  )

  expect_error(
    gram:::Tracing(
      stem = "x", sample_rate = 1000, samples = c(1, 2),
      channels = "I", values = list(I = c(1, 2), II = c(1, 2)),
      units = "physical", ops = list()
    ),
    "exactly one vector per channel"
  )

  expect_error(
    gram:::Tracing(
      stem = "x", sample_rate = 1000, samples = c(1, 2, 3),
      channels = "I", values = list(I = c(1, 2)),
      units = "physical", ops = list()
    ),
    "as long as @samples"
  )
})
