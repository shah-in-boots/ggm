# Choose which channels are on screen

A Shiny module that lists the channels a record carries and reports
which are selected. It is a plain add-on: the server half returns a
reactive and does not touch any plot, so one line at the call site
connects it to whatever should respond.

## Usage

``` r
gram_channelsUI(
  id,
  channels,
  variant = c("checkbox", "dropdown"),
  selected = NULL,
  label = NULL
)

gram_channelsServer(id)
```

## Arguments

- id:

  Module id, matched between the UI and server halves.

- channels:

  A `StudyCache`, whose WFDB header names the channels, or a character
  vector of channel labels.

- variant:

  Shape of the control. `"checkbox"` gives a column, one row per
  channel; `"dropdown"` gives a multi-select. Both choose the same
  thing, so this is a display decision only.

- selected:

  Channels selected at startup, as labels or as 1-based indices.
  Defaults to all of them.

- label:

  Control label. `NULL` draws none, which suits a control that already
  sits under a heading.

## Value

`gram_channelsUI()` returns a Shiny input control.
`gram_channelsServer()` returns a reactive giving the selected channel
indices: 1-based into `channels`, ascending, and `integer(0)` when
nothing is selected. Labels are `channels[chosen()]`.

## Details

The module reports a selection and stops there; one line connects it to
whatever should respond.
[`gram_harness()`](https://shah-in-boots.github.io/gram/reference/gram_harness.md)
wires it to a
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)
viewer through the plotting verbs:

    # ui
    gram_channelsUI("channels", cache)

    # server
    chosen <- gram_channelsServer("channels")
    shiny::observe({
      gm_set_visible(gm_proxy("viewer"), chosen())
    })

Because the widget already holds every channel it was built with, that
costs no further read of the record – it only moves lanes on and off
screen. Those two verbs are package-internal for now, so outside gram
drive your own output from `chosen()` instead.

The list is fixed when the UI is built. Pass the channels the viewer
actually loaded, which is what can be switched back on – for a study
opened whole, that is every channel in the header.
