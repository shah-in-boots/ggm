# Canonicalise a viewer selection to a sample range

Canonicalise a viewer selection to a sample range

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
range, clamped to the record. `NULL` when nothing is selected and when
the selection holds no samples.

## See also

Other controller:
[`gram_channels`](https://shah-in-boots.github.io/gram/reference/gram_channels.md),
[`gram_harness()`](https://shah-in-boots.github.io/gram/reference/gram_harness.md)
