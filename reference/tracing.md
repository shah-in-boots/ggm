# Open a signal window as a tracing

Reads one window from the canonical signal and returns a `Tracing` with
an empty script. Verbs append operations to it.

## Usage

``` r
tracing(
  cache,
  begin = NULL,
  end = NULL,
  interval = NULL,
  channels = NULL,
  units = c("physical", "digital"),
  max_points = 2000
)
```

## Arguments

- cache:

  A `StudyCache` from
  [`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md).

- begin, end:

  Times delimiting a half-open range. These follow
  `EGM::validate_time_parameters()`: time-only character values are
  elapsed from the record start, dated character values and `POSIXt`
  objects are absolute, and `difftime` values are elapsed durations.
  Numeric values are not accepted.

- interval:

  A duration after `begin` that takes precedence over `end`. Numeric
  values are seconds; compact durations such as `"100 ms"` are also
  accepted.

- channels:

  Channel labels or indices. Defaults to all channels.

- units:

  Units passed to
  [`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html).

- max_points:

  Largest number of points kept per channel. Longer windows are
  decimated by a fixed stride, which can drop a narrow deflection; keep
  presentation windows short rather than raising this.

## Value

A `Tracing`.

## See also

Other tracing:
[`at()`](https://shah-in-boots.github.io/gram/reference/at.md),
[`gram_tracing()`](https://shah-in-boots.github.io/gram/reference/gram_tracing.md),
[`tracing_spec()`](https://shah-in-boots.github.io/gram/reference/tracing_spec.md)
