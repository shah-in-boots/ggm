skip_if_not_installed("shiny")

leads <- c("HIS D", "CS 1-2", "RV 1-2")

# the rendered control, as one string, which is where the labels and the
# namespaced input id have to show up
markup <- function(tag) paste(as.character(tag), collapse = "")


# ui --------------------------------------------------------------------

test_that("the control lists every channel and namespaces its input", {
  ui <- markup(gram_channelsUI("picker", leads))

  for (lead in leads) {
    expect_match(ui, lead, fixed = TRUE)
  }
  expect_match(ui, "picker-channels", fixed = TRUE)
})

test_that("the control reads its channels off a StudyCache header", {
  cache <- demo_cache()
  ui <- markup(gram_channelsUI("picker", cache))

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
  # a checkbox column and a dropdown offer the same channels
  boxes <- markup(gram_channelsUI("picker", leads, variant = "checkbox"))
  menu <- markup(gram_channelsUI("picker", leads, variant = "dropdown"))

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
  # the attribute, not the bare word: shiny writes checked="checked", so
  # counting "checked" counts every box twice
  ticked <- function(ui) {
    lengths(regmatches(ui, gregexpr("checked=\"checked\"", ui, fixed = TRUE)))[[1L]]
  }

  expect_equal(ticked(markup(gram_channelsUI("picker", leads))), length(leads))

  # by label or by index, and both land on the same channel
  by_label <- markup(gram_channelsUI("picker", leads, selected = "CS 1-2"))
  by_index <- markup(gram_channelsUI("picker", leads, selected = 2))
  expect_equal(by_label, by_index)
  expect_equal(ticked(by_label), 1L)
})

test_that("a starting set that names no channel is refused", {
  expect_error(
    gram_channelsUI("picker", leads, selected = "V6"),
    "does not carry: V6"
  )
  expect_error(gram_channelsUI("picker", leads, selected = 0), "outside the 3")
  expect_error(gram_channelsUI("picker", leads, selected = 4), "outside the 3")
  expect_error(gram_channelsUI("picker", leads, selected = NA), "labels or 1-based")
  expect_error(gram_channelsUI("picker", character()), "non-empty character")
  expect_error(gram_channelsUI("picker", leads, variant = "carousel"), "'arg'")
})


# server ----------------------------------------------------------------

test_that("the module reports the selection as ascending channel indices", {
  shiny::testServer(gram_channelsServer, args = list(id = "picker"), {
    # the control reports character values, whatever its shape
    session$setInputs(channels = c("3", "1"))
    expect_identical(session$returned(), c(1L, 3L))

    session$setInputs(channels = "2")
    expect_identical(session$returned(), 2L)
  })
})

test_that("an empty selection is an empty selection, not a missing one", {
  # clearing every channel is a thing a reader can do; it must reach the
  # caller as a real empty set rather than NULL, which would read as "not
  # ready yet" and leave the viewer showing a stale set
  shiny::testServer(gram_channelsServer, args = list(id = "picker"), {
    session$setInputs(channels = character())
    expect_identical(session$returned(), integer())
  })
})
