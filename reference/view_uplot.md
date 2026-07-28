# View a study window with the uPlot backend

`view_uplot()` is a backend-specific development viewer. It reads a
fixed interval from the canonical WFDB signal, adapts the result to
uPlot's aligned column format, and returns the standalone uPlot widget.
It is useful for exercising and testing the uPlot backend without a
Shiny controller.

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
  `EGM::validate_time_parameters()`: time-only character values are
  elapsed from the record start, dated character values and `POSIXt`
  objects are absolute, and `difftime` values are elapsed durations.
  Numeric values are not accepted.

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

## Details

The widget contains only the requested `begin` to `end` or `interval`
range. When neither `end` nor `interval` is supplied, the viewer reads
ten seconds from `begin`. Drag horizontally to zoom into that loaded
range, scroll horizontally (or use Shift+wheel) to pan, and double-click
to reset the range. A future interactive study controller can manage
dynamic viewport reads while reusing the same uPlot backend.
