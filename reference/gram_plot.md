# Create a uPlot-backed electrogram widget

`gram_plot()` is the low-level plotting primitive. It renders one uPlot
per signal channel so each panel has an independent y-scale, while
synchronizing the x-range and cursor across panels. Data must already be
in uPlot's aligned column format: a list containing one shared x vector
followed by one y vector per signal series. Use
[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md)
to read and display a raw window from a `StudyCache` directly.

## Usage

``` r
gram_plot(
  columns,
  scale = list(kind = "index", rate = 1),
  series = NULL,
  panel_height = 120,
  width = NULL,
  height = NULL,
  elementId = NULL
)
```

## Arguments

- columns:

  List of numeric vectors in the form
  `list(x, channel_1, channel_2, ...)`. All vectors must have equal
  length.

- scale:

  X-scale description. `kind` may be `"index"` for sample numbers,
  `"elapsed"` for elapsed seconds, or `"timestamp"` for Unix timestamps.

- series:

  Optional list of per-channel display lists. Each entry may contain
  `label` and `color`.

- panel_height:

  Height of each channel panel in CSS pixels.

- width, height:

  Optional widget dimensions.

- elementId:

  Optional HTML element id.

## Value

An `htmlwidget`.
