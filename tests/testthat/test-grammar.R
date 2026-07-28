grammar_cache <- function() {
  record <- file.path(system.file("extdata", package = "gram"), "bard-egm.dat")
  study_cache(record, cache_dir = tempdir())
}

test_that("a script builds a tracing without naming the study", {
  x <- eval_tracing(
    'tracing(begin = "00:00:00", interval = "300 ms",
             channels = c("HIS D", "RV 1-2")) |>
       reveal() |>
       add_arrow(from = at(50, "RV 1-2"), to = at(120, "HIS D"), label = "VA")',
    grammar_cache()
  )

  expect_true(S7::S7_inherits(x, gram:::Tracing))
  expect_equal(vapply(x@ops, `[[`, character(1), "type"), c("reveal", "arrow"))
})

test_that("the verb environment is sealed", {
  env <- gram_verbs(grammar_cache())

  expect_identical(parent.env(env), emptyenv())
  expect_setequal(
    ls(env),
    c("tracing", "at", "reveal", "add_arrow", "emphasize", "c", ":")
  )
})

test_that("calls outside the grammar are refused before evaluation", {
  cache <- grammar_cache()
  sentinel <- tempfile()
  writeLines("intact", sentinel)

  # each of these must fail at the whitelist walk, not at evaluation
  expect_error(eval_tracing('system("echo no")', cache), "not part of the")
  expect_error(eval_tracing('library(utils)', cache), "not part of the")
  expect_error(eval_tracing(sprintf('file.remove("%s")', sentinel), cache),
               "not part of the")
  expect_error(eval_tracing('base::print(1)', cache), "no packages to reach")
  expect_error(eval_tracing('x <- 1', cache), "not part of the")
  expect_error(eval_tracing('(function() 1)()', cache), "computed call")

  # the walk runs before any evaluation, so nothing executed
  expect_equal(readLines(sentinel), "intact")
})

test_that("undefined names are refused", {
  cache <- grammar_cache()

  expect_error(eval_tracing("everything", cache), "not defined in the")
  expect_error(eval_tracing("wiggle()", cache), "not part of the")
})

test_that("a script must end in a tracing", {
  cache <- grammar_cache()

  expect_error(eval_tracing('at(1, "HIS D")', cache), "must end in a tracing")
  expect_error(eval_tracing("", cache), "empty")
  expect_error(eval_tracing("tracing(", cache), "could not parse")
  expect_error(eval_tracing(c("a", "b"), cache), "single string")
})

test_that("errors from the verbs reach the caller intact", {
  expect_error(
    eval_tracing(
      'tracing(begin = "00:00:00", interval = "300 ms", channels = "HIS D") |>
         emphasize(at(50, "CS 1-2"))',
      grammar_cache()
    ),
    "not in this tracing"
  )
})
