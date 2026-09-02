# Open a WFDB record as a StudyCache handle

Open a WFDB record as a StudyCache handle

## Usage

``` r
study_cache(path, annotators = NULL, raw_ext = "dat", header_ext = "hea")
```

## Arguments

- path:

  Any file in the record group, or a bare stem.

- annotators:

  Optional WFDB annotator extensions to require, such as `"qrs"` or
  `"ann"`. `NULL` discovers existing sidecars.

- raw_ext:

  Signal extension, without the dot.

- header_ext:

  Header extension, without the dot.

## Value

A `StudyCache`.
