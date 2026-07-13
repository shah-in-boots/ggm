# Build the derived overview cache for a WFDB study

Streams raw signal chunks from
[`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html),
reduces them to bucket extrema, and writes all overview levels to
`<stem>.cache.parquet`. The raw `.dat` file remains the source for
high-resolution reads.

## Usage

``` r
build_study_cache(
  cache,
  bucket_samples = 64L,
  level_factor = 4L,
  target_top_rows = 1e+05,
  max_levels = 6L,
  chunk_seconds = 60,
  units = c("physical", "digital"),
  overwrite = FALSE
)
```

## Arguments

- cache:

  A `StudyCache` from
  [`study_cache()`](https://shah-in-boots.github.io/ggm/reference/study_cache.md).

- bucket_samples:

  Finest overview bucket size, in samples.

- level_factor:

  Geometric factor between overview levels.

- target_top_rows:

  Add coarser levels until the top level has at most this many buckets.

- max_levels:

  Safety cap on overview depth, excluding raw level 0.

- chunk_seconds:

  Raw read size during the streaming pass.

- units:

  Units to cache, passed to
  [`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html).

- overwrite:

  Rebuild even if a cache already exists.

## Value

The updated `StudyCache`.
