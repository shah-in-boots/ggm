# Read raw WFDB signal for a visible window

Thin wrapper around
[`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html)
that uses the parsed header stored in the `StudyCache`.

## Usage

``` r
read_study_signal(
  cache,
  begin = 0,
  end = NA_real_,
  channels = NULL,
  units = c("physical", "digital")
)
```

## Arguments

- cache:

  A `StudyCache`.

- begin, end:

  Window bounds in seconds.

- channels:

  Channel labels or indices. Defaults to all channels.

- units:

  Units passed to
  [`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html).

## Value

An `EGM` signal table.
