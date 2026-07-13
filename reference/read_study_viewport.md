# Read the appropriate data for a viewport

Read the appropriate data for a viewport

## Usage

``` r
read_study_viewport(
  cache,
  begin,
  end,
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

  Window bounds in seconds.

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
