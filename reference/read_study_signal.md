# Read raw WFDB signal for a visible window

Thin wrapper around
[`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html)
that uses the parsed header stored in the `StudyCache`.

## Usage

``` r
read_study_signal(
  cache,
  begin = NULL,
  end = NULL,
  interval = NULL,
  channels = NULL,
  units = c("physical", "digital")
)
```

## Arguments

- cache:

  A `StudyCache`.

- begin, end:

  Times delimiting a half-open range. These follow
  [`EGM::validate_time_parameters()`](https://shah-in-boots.github.io/EGM/reference/validate_time_parameters.html):
  time-only character values are elapsed from the record start, dated
  character values and `POSIXt` objects are absolute, and `difftime`
  values are elapsed durations. Numeric values are not accepted.

- interval:

  A duration after `begin` that takes precedence over `end`. Numeric
  values are seconds; compact durations such as `"100 ms"` are also
  accepted.

- channels:

  Channel labels or indices. Defaults to all channels.

- units:

  Units passed to
  [`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html).

## Value

An `EGM` signal table.
