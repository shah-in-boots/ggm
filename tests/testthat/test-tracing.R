demo_cache <- function() {
  record <- file.path(system.file("extdata", package = "gram"), "bard-egm.dat")
  study_cache(record, cache_dir = tempdir())
}

demo_tracing <- function(cache = demo_cache()) {
  tracing(
    cache,
    begin = "00:00:00",
    interval = "500 ms",
    channels = c("HIS D", "RV 1-2")
  )
}

test_that("tracing reads a window and starts with an empty script", {
  x <- demo_tracing()

  expect_equal(x@channels, c("HIS D", "RV 1-2"))
  expect_equal(length(x@samples), 500L)
  expect_equal(x@samples[[1L]], 0)
  expect_equal(lengths(x@values), c("HIS D" = 500L, "RV 1-2" = 500L))
  expect_length(x@ops, 0L)
})

test_that("long windows decimate to max_points with a warning", {
  expect_warning(
    x <- tracing(
      demo_cache(),
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
  x <- demo_tracing() |>
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
  x <- demo_tracing()

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
  spec <- demo_tracing() |>
    reveal() |>
    add_arrow(from = at(100, "RV 1-2"), to = at(200, "HIS D"), label = "VA") |>
    tracing_spec()

  expect_equal(spec$version, 1L)
  expect_equal(spec$height, 240)
  expect_equal(vapply(spec$ops, `[[`, character(1), "type"),
               c("reveal", "arrow"))

  # one trace path per channel, one arrow, and the label the verb named
  expect_equal(lengths(regmatches(
    spec$svg, gregexpr('class="gram-trace"', spec$svg, fixed = TRUE)
  ))[[1L]], 2L)
  expect_match(spec$svg, 'id="gram-arrow-1"', fixed = TRUE)
  expect_match(spec$svg, ">VA</text>", fixed = TRUE)
  expect_match(spec$svg, "viewBox=\"0 0 1000 240\"", fixed = TRUE)
})

test_that("channel labels are escaped into the markup", {
  x <- demo_tracing()
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
  x <- demo_tracing()
  geom <- gram:::tracing_geometry(x)

  top <- gram:::geom_baseline(x, "HIS D")
  bottom <- gram:::geom_baseline(x, "RV 1-2")

  expect_equal(top, 60)
  expect_equal(bottom, 180)
  expect_equal(gram:::geom_x(geom, x@samples[[1L]]), 0)
  expect_equal(gram:::geom_x(geom, x@samples[[length(x@samples)]]), 1000)
})
