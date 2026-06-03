# Open a study

Bind a WFDB record to a lightweight `ggm_study` object. Only the header
is read on open (cheap); signal samples are read on demand by
[`get_window()`](https://shah-in-boots.github.io/ggm/reference/get_window.md).

## Usage

``` r
open_study(record, record_dir = ".")

is_study(x)
```

## Arguments

- record:

  Record name, without file extension (e.g. `"bard-egm"`). The
  `.hea`/`.dat` files are expected to share this stem.

- record_dir:

  Directory containing the record's files. Defaults to the current
  directory.

- x:

  A `ggm_study` (for `is_study()`) or any object.

## Value

A `ggm_study`: a list with the record location, the parsed `EGM`
`header_table`, and convenience fields pulled from the header
(`frequency` in Hz, `n_samples`, `channels`, `start_time`, and
`duration` in seconds).

`is_study()` returns a length-one logical.

## Details

This wraps
[`EGM::read_header()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html)
and pulls the recording metadata from its `record_line` attribute. The
signal store stays canonical in `EGM`; `ggm` only remembers how to reach
it.

## Examples

``` r
if (FALSE) { # \dontrun{
study <- open_study("bard-egm", system.file("extdata", package = "ggm"))
study
} # }
```
