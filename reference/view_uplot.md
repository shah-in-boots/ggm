# View a study window with the uPlot backend

Reads one window from the canonical WFDB signal, adapts it to uPlot's
aligned column format, and returns the standalone widget. When neither
`end` nor `interval` is supplied it reads ten seconds from `begin`.

## Usage

``` r
view_uplot(
  cache,
  begin = NULL,
  end = NULL,
  interval = NULL,
  channels = NULL,
  units = c("physical", "digital"),
  width = NULL,
  height = 500
)
```

## Arguments

- cache:

  A `StudyCache` created by
  [`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md).

- begin, end:

  Times delimiting a half-open range. These follow
  [`EGM::validate_time_parameters()`](https://shah-in-boots.github.io/EGM/reference/validate_time_parameters.html):
  time-only character values are elapsed from the record start, dated
  character values and `POSIXt` objects are absolute, and `difftime`
  values are elapsed durations. Numeric values are not accepted.

- interval:

  A duration after `begin` that takes precedence over `end`. Numeric
  values are seconds; compact durations such as `"100 ms"` are also
  accepted.

- channels:

  Channel labels or indices. Defaults to all channels.

- units:

  Signal units passed to
  [`read_study_signal()`](https://shah-in-boots.github.io/gram/reference/read_study_signal.md).

- width, height:

  Optional widget dimensions.

## Value

An `htmlwidget`.

## See also

Other backend viewers:
[`normalize_selection()`](https://shah-in-boots.github.io/gram/reference/normalize_selection.md)
