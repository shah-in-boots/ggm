# Whole-study overview (not yet implemented)

Planned for milestone **M2.5**. Returns the zoomed-out navigation map: a
faint downsampled signal tier (from the signal pyramid) plus the sharp
event layer (aggregated annotation spans/ticks/flags) you scroll by.

## Usage

``` r
get_overview(study, channels = NULL, filter = NULL)
```

## Arguments

- study:

  A `ggm_study` from
  [`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md).

- channels:

  Channel labels to include, or `NULL` for all.

- filter:

  Optional annotation filter expression for the event layer.

## Value

(Planned) overview data for the two-layer map. Currently errors.
