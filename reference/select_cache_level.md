# Pick the best source level for a viewport

Returns raw level 0 when the visible window is already near screen
resolution. Otherwise it selects the finest overview level whose emitted
extrema stay near `points_per_pixel`.

## Usage

``` r
select_cache_level(cache, window_seconds, pixel_width, points_per_pixel = 4)
```

## Arguments

- cache:

  A built `StudyCache`.

- window_seconds:

  Visible time span.

- pixel_width:

  Plot width in device pixels.

- points_per_pixel:

  Target maximum rendered points per pixel.

## Value

One row of `cache@levels`.
