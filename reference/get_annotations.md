# Query annotations over a window (not yet implemented)

Planned for milestone **M3**. Returns a filtered view of the study's
annotations, keyed on `sample` + `channel`, for drawing and "jump to
next event" navigation.

## Usage

``` r
get_annotations(study, range = NULL, filter = NULL)
```

## Arguments

- study:

  A `ggm_study` from
  [`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md).

- range:

  Optional sample or time range to restrict to.

- filter:

  Optional filter expression (e.g. `type == "AVB"`).

## Value

(Planned) an annotation table. Currently errors.
