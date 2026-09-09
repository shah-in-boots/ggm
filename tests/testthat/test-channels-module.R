skip_if_not_installed("shiny")

leads <- c("HIS D", "CS 1-2", "RV 1-2")


# ui --------------------------------------------------------------------

test_that("the control lists every channel and namespaces its input", {
  ui <- paste(as.character(gram_channelsUI("picker", leads)), collapse = "")

  for (lead in leads) {
    expect_match(ui, lead, fixed = TRUE)
  }
  expect_match(ui, "picker-channels", fixed = TRUE)
})

test_that("the control reads its channels off a StudyCache header", {
  cache <- study_cache(system.file("extdata", "bard-egm.hea", package = "gram"))
  ui <- paste(as.character(gram_channelsUI("picker", cache)), collapse = "")

  # every channel the WFDB header names, and no more
  for (channel in cache@channels) {
    expect_match(ui, channel, fixed = TRUE)
  }
  expect_equal(
    lengths(regmatches(ui, gregexpr("type=\"checkbox\"", ui, fixed = TRUE)))[[1L]],
    length(cache@channels)
  )
})

test_that("the shape of the control is a display choice, not a different module", {
  boxes <- paste(
    as.character(gram_channelsUI("picker", leads, variant = "checkbox")),
    collapse = ""
  )
  menu <- paste(
    as.character(gram_channelsUI("picker", leads, variant = "dropdown")),
    collapse = ""
  )

  expect_match(boxes, "type=\"checkbox\"", fixed = TRUE)
  expect_match(menu, "<select", fixed = TRUE)
  expect_match(menu, "multiple", fixed = TRUE)
  expect_false(grepl("type=\"checkbox\"", menu, fixed = TRUE))

  for (lead in leads) {
    expect_match(boxes, lead, fixed = TRUE)
    expect_match(menu, lead, fixed = TRUE)
  }
})

test_that("everything is selected unless a starting set is named", {
  all <- paste(as.character(gram_channelsUI("picker", leads)), collapse = "")
  by_label <- paste(
    as.character(gram_channelsUI("picker", leads, selected = "CS 1-2")),
    collapse = ""
  )
  by_index <- paste(
    as.character(gram_channelsUI("picker", leads, selected = 2)),
    collapse = ""
  )

  # the attribute, not the bare word: shiny writes checked="checked", so
  # counting "checked" counts every box twice
  expect_equal(
    lengths(regmatches(all, gregexpr("checked=\"checked\"", all, fixed = TRUE)))[[1L]],
    length(leads)
  )

  # by label or by index, and both land on the same channel
  expect_equal(by_label, by_index)
  expect_equal(
    lengths(regmatches(
      by_label, gregexpr("checked=\"checked\"", by_label, fixed = TRUE)
    ))[[1L]],
    1L
  )
})

test_that("a starting set that names no channel is refused", {
  expect_error(
    gram_channelsUI("picker", leads, selected = "V6"),
    "does not carry: V6"
  )
  expect_error(gram_channelsUI("picker", leads, selected = 0), "whole 1-based indices within the 3 channels")
  expect_error(gram_channelsUI("picker", leads, selected = 4), "whole 1-based indices within the 3 channels")
  expect_error(gram_channelsUI("picker", leads, selected = NA), "labels or 1-based")
  expect_error(gram_channelsUI("picker", character()), "non-empty character")
  expect_error(gram_channelsUI("picker", leads, variant = "carousel"), "'arg'")
})


# server ----------------------------------------------------------------

test_that("the module reports the selection as ascending channel indices", {
  shiny::testServer(gram_channelsServer, args = list(id = "picker"), {
    session$setInputs(channels = c("3", "1"))
    expect_identical(session$returned(), c(1L, 3L))

    session$setInputs(channels = "2")
    expect_identical(session$returned(), 2L)
  })
})

test_that("an empty selection is an empty selection, not a missing one", {
  # a real empty set, not NULL, which would read as "not ready yet"
  shiny::testServer(gram_channelsServer, args = list(id = "picker"), {
    session$setInputs(channels = character())
    expect_identical(session$returned(), integer())
  })
})
