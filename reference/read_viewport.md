# Read the data needed to draw a window

Routes a sample window to the raw signal or to an overview level. Raw is
used when the window already holds few enough samples to draw; otherwise
the finest overview level that keeps the plotted points near the
design's four per pixel per channel. An overview is never used for
measurement or snapping; it is for drawing.

## Usage

``` r
read_viewport(
  cache,
  window,
  channels = NULL,
  width_px = NULL,
  resolution = c("auto", "raw", "overview")
)
```

## Arguments

- cache:

  A `StudyCache`.

- window:

  A list holding `begin` and `end` sample indices delimiting a half-open
  range, as
  [`normalize_selection()`](https://shah-in-boots.github.io/gram/reference/normalize_selection.md)
  returns.

- channels:

  Channel labels or indices. Defaults to all channels.

- width_px:

  Width of the plot in pixels. Required unless `resolution = "raw"`.

- resolution:

  `"auto"` chooses by window and width, `"raw"` always reads the signal,
  and `"overview"` always reads a cache level, the finest one when the
  window is small.

## Value

A list with `data`, `resolution`, and `level`. For raw reads `data` is
the signal table (`sample` plus one column per channel), `resolution` is
`"raw"` and `level` is `0`. For overview reads `data` is a named list
with one `list(sample, value)` per channel, the minima and maxima of
each bucket in sample order with a flat bucket's pair collapsed to one
point; `resolution` is the bucket size in samples and `level` its
position in the pyramid. Extrema fall at different samples per channel,
which is why the two shapes differ.

## See also

[`build_overview()`](https://shah-in-boots.github.io/gram/reference/build_overview.md),
[`read_study_signal()`](https://shah-in-boots.github.io/gram/reference/read_study_signal.md)
