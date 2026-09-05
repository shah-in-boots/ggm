# Reduce a signal to per-bucket extrema

Splits `values` into consecutive runs of `bucket` and returns the
minimum and maximum of each run together with the sample index at which
each occurred. It serves the first overview level, where `values` is raw
signal, and every merge above it, where `values` is the level below's
minima or maxima and `samples` their positions.

## Usage

``` r
gm_bucket_extrema(values, samples, bucket)
```

## Arguments

- values:

  Numeric vector.

- samples:

  Integer vector, the sample index of each value.

- bucket:

  Number of consecutive values per bucket.

## Value

A data frame with one row per bucket and columns `min`, `min_at`, `max`,
`max_at`. A bucket containing `NA` reports `NA`, so a gap in the signal
stays a gap in the overview.
