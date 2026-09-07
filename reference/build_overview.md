# Build the overview cache for a study

Streams the record through
[`read_viewport()`](https://shah-in-boots.github.io/gram/reference/read_viewport.md)
in chunks, reduces each chunk to per-bucket minima and maxima with
[`gm_bucket_extrema()`](https://shah-in-boots.github.io/gram/reference/gm_bucket_extrema.md),
merges the result upward until one bucket covers the whole record, and
writes the stacked levels beside the record as `<stem>.gram.parquet` (or
`.rds`) with a `cache` section in `<stem>.gram.json`. Peak memory is one
chunk, not the record.

## Usage

``` r
build_overview(
  cache,
  chunk_seconds = 60,
  format = c("parquet", "rds"),
  rebuild = FALSE
)
```

## Arguments

- cache:

  A `StudyCache` from
  [`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md).

- chunk_seconds:

  Seconds of signal read per pass. Bounds memory during the build; it
  does not change the result.

- format:

  On-disk format of the table. Parquet reads a subset of channels
  without touching the rest, which is what keeps a viewport read fast;
  rds reads everything.

- rebuild:

  Build even when a usable overview already exists.

## Value

The handle, invisibly. The overview lives on disk, not in the handle, so
no reassignment is needed.

## Details

The table has one row per bucket and columns `level`, `start` (first
sample of the bucket) and, per channel position `i`, `ch<i>.min`,
`ch<i>.min_at`, `ch<i>.max`, `ch<i>.max_at`. Values are in physical
units. Time is never stored; it is `sample / sample_rate`.

## See also

[`read_viewport()`](https://shah-in-boots.github.io/gram/reference/read_viewport.md)

Other viewport:
[`read_study_signal()`](https://shah-in-boots.github.io/gram/reference/read_study_signal.md),
[`read_viewport()`](https://shah-in-boots.github.io/gram/reference/read_viewport.md)
