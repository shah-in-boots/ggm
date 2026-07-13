# Open a WFDB record as a StudyCache handle

Accepts a bare record path or any sibling file from the group, derives
the required `.dat` and `.hea` paths, reads the WFDB header with
[`EGM::read_header()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html),
discovers optional annotation sidecars, and attaches an existing cache
manifest when present.

## Usage

``` r
study_cache(
  path,
  cache_dir = NULL,
  annotators = NULL,
  raw_ext = "dat",
  header_ext = "hea"
)
```

## Arguments

- path:

  Any file in the record group, or a bare stem.

- cache_dir:

  Directory for `*.cache.parquet` and `*.cache.json`. Defaults to the
  record directory when writable, otherwise a per-user cache directory.

- annotators:

  Optional WFDB annotator extensions to require, such as `"qrs"` or
  `"ann"`. `NULL` discovers existing sidecars.

- raw_ext:

  Signal extension, without the dot.

- header_ext:

  Header extension, without the dot.

## Value

A `StudyCache`.
