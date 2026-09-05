# Open a WFDB record as a StudyCache handle

Validates the record group, reads the header with
[`EGM::read_header()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html),
discovers annotation sidecars, and remembers where gram's own files for
this record live. Nothing is read from the signal and nothing is
written.

## Usage

``` r
study_cache(
  path,
  cache_dir = NULL,
  annotators = NULL,
  data_ext = "dat",
  header_ext = "hea"
)
```

## Arguments

- path:

  Any file in the record group, or a bare stem.

- cache_dir:

  Directory holding `<stem>.gram.json` and the overview table. Defaults
  to the record directory. Point it elsewhere when the study folder is
  read-only; the same `cache_dir` must then be given every time the
  study is opened, since that is where the handle looks.

- annotators:

  Optional WFDB annotator extensions to require, such as `"qrs"` or
  `"ann"`. `NULL` discovers existing sidecars.

- data_ext:

  Signal extension, without the dot.

- header_ext:

  Header extension, without the dot.

## Value

A `StudyCache`.

## See also

[`build_overview()`](https://shah-in-boots.github.io/gram/reference/build_overview.md),
[`read_viewport()`](https://shah-in-boots.github.io/gram/reference/read_viewport.md),
[`read_study_signal()`](https://shah-in-boots.github.io/gram/reference/read_study_signal.md)
