# Read the cache section of a study manifest

`<stem>.gram.json` is shared between the parts of gram that write beside
a record; each owns one section. This reads the `cache` section and
decides whether the overview it describes may be used for the open
record.

## Usage

``` r
gm_read_manifest(cache)
```

## Arguments

- cache:

  A `StudyCache`.

## Value

The `cache` section as a list, or `NULL` when the manifest or the
section is absent, the section was written by another format version,
its fingerprint is not the open record's (the record changed since the
build), or the table it names is missing. `NULL` is the answer to "may I
use this overview", and every caller treats it as "not built" rather
than serving a stale reduction as if it were current.
