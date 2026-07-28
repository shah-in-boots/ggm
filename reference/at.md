# Refer to a point on a channel

`at()` names a sample on a channel so a verb can resolve it to a
position. Annotation-resolved endpoints (`A[1]`, `V_stim[last]`) will
replace this once the annotation reader lands; until then the sample is
given directly.

## Usage

``` r
at(sample, channel)
```

## Arguments

- sample:

  Sample index.

- channel:

  Channel label.

## Value

A `gram_at` reference.

## See also

Other tracing:
[`gram_tracing()`](https://shah-in-boots.github.io/gram/reference/gram_tracing.md),
[`tracing()`](https://shah-in-boots.github.io/gram/reference/tracing.md),
[`tracing_spec()`](https://shah-in-boots.github.io/gram/reference/tracing_spec.md)
