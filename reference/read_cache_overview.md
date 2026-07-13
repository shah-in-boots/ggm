# Read an overview cache window

Read an overview cache window

## Usage

``` r
read_cache_overview(
  cache,
  begin,
  end,
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

  Window bounds in seconds.

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
