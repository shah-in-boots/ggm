# Read an overview cache window

Read an overview cache window

## Usage

``` r
read_cache_overview(
  cache,
  begin = NULL,
  end = NULL,
  interval = NULL,
  channels = NULL,
  level = NULL,
  pixel_width = 1000,
  points_per_pixel = 4
)
```

## Arguments

- cache:

  A built `StudyCache`.

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

  Channel labels. Defaults to all channels.

- level:

  Overview level to read. Defaults to automatic level selection.

- pixel_width:

  Plot width used when `level = NULL`.

- points_per_pixel:

  Target maximum rendered points per pixel.

## Value

Data frame with `sample`, `time`, `channel`, `value`, and `statistic`.
