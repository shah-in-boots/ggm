# Read the appropriate data for a viewport

Read the appropriate data for a viewport

## Usage

``` r
read_study_viewport(
  cache,
  begin = NULL,
  end = NULL,
  interval = NULL,
  channels = NULL,
  pixel_width,
  resolution = c("auto", "raw", "overview"),
  points_per_pixel = 4,
  units = c("physical", "digital")
)
```

## Arguments

- cache:

  A `StudyCache`.

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

  Channel labels or indices.

- pixel_width:

  Plot width in device pixels.

- resolution:

  `"auto"`, `"raw"`, or `"overview"`.

- points_per_pixel:

  Target maximum rendered points per pixel.

- units:

  Raw read units.

## Value

A list with `data`, `resolution`, and `level`.
