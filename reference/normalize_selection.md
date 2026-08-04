# Canonicalise a viewer selection to a sample range

A
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)
widget reports a completed drag as an `<outputId>_selection` Shiny input
carrying `xmin` and `xmax` in the widget's display units – elapsed
seconds, for the x-scale
[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md)
builds. Sample index is the canonical key, so the conversion happens
here once rather than in every caller.

## Usage

``` r
normalize_selection(cache, selection)
```

## Arguments

- cache:

  A `StudyCache`.

- selection:

  The widget's selection input: a list holding `xmin` and `xmax` in
  elapsed seconds. `NULL` before anything has been selected.

## Value

A list with `begin` and `end` sample indices delimiting a half-open
range, clamped to the record. `NULL` both when nothing is selected yet
and when the selection collapses to no samples, so a stray click leaves
the caller's current window standing rather than blanking it.

## See also

Other backend viewers:
[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md)
