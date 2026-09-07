# View a study window with plotly

Reads one window from a `StudyCache` and returns the plotly widget:
cache and window in, widget out, no controller. It is the one-call check
that this backend draws a window, and it lives beside the spec it
exercises. Needs the `plotly` package, whose plotly.js bundle is
borrowed rather than vendored.

## Usage

``` r
view_plotly(
  cache,
  window = NULL,
  channels = NULL,
  width_px = 1200,
  resolution = c("auto", "raw", "overview"),
  width = NULL,
  height = 500
)
```

## Arguments

- cache:

  A `StudyCache` created by
  [`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md).

- window:

  Sample range as `list(begin =, end =)`, half-open. Defaults to the
  whole record.

- channels:

  Channel labels or indices. Defaults to all channels.

- width_px:

  Width of the plot in pixels. Required unless `resolution = "raw"`.

- resolution:

  `"auto"` chooses by window and width, `"raw"` always reads the signal,
  and `"overview"` always reads a cache level, the finest one when the
  window is small.

- width, height:

  Optional widget dimensions.

## Value

An `htmlwidget`.

## Details

The window is given in samples, the same currency
[`read_viewport()`](https://shah-in-boots.github.io/gram/reference/read_viewport.md)
and
[`normalize_selection()`](https://shah-in-boots.github.io/gram/reference/normalize_selection.md)
speak. The whole record is a valid window and the default.

## See also

[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md),
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)

Other backend viewers:
[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md)
