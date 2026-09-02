# Choose which channels are on screen

A Shiny module that lists the channels a record carries and reports
which are selected. The server half returns a reactive and touches no
plot.

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
  channel; `"dropdown"` gives a multi-select.

- selected:

  Channels selected at startup, as labels or as 1-based indices.
  Defaults to all of them.

- label:

  Control label. `NULL` draws none.

## Value

`gram_channelsUI()` returns a Shiny input control.
`gram_channelsServer()` returns a reactive giving the selected channel
indices: 1-based into `channels`, ascending, and `integer(0)` when
nothing is selected. Labels are `channels[chosen()]`.
