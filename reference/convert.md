# Convert between sample index and time

The sample index (an integer count of samples from the start of the
record) is the canonical key used for storage and joins; time in seconds
is the display unit. Conversion is exact given the recording's sampling
frequency: `time = sample / frequency` and
`sample = round(time * frequency)`.

## Usage

``` r
time_to_sample(time, frequency)

sample_to_time(sample, frequency)
```

## Arguments

- time:

  Numeric vector of times, in **seconds**.

- frequency:

  Sampling frequency in Hz (samples per second). A single positive
  number, typically `study$frequency`.

- sample:

  Numeric (integer) vector of **sample indices**.

## Value

- `time_to_sample()`: an integer vector of sample indices (rounded).

- `sample_to_time()`: a double vector of times in seconds.

## Details

`time_to_sample()` rounds to the nearest sample because a time need not
land exactly on a sample boundary; `sample_to_time()` is exact.
Round-tripping a valid sample index (`sample_to_time()` then
`time_to_sample()`) returns the original index.

## Examples

``` r
time_to_sample(c(0, 1, 1.5), frequency = 1000)
#> [1]    0 1000 1500
sample_to_time(c(0L, 1000L, 1500L), frequency = 1000)
#> [1] 0.0 1.0 1.5
```
