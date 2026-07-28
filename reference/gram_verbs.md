# Build the sealed environment a tracing script runs in

The returned environment holds the tracing verbs and nothing else. Its
parent is [`emptyenv()`](https://rdrr.io/r/base/environment.html), so a
name the grammar does not define cannot be reached from a script.

## Usage

``` r
gram_verbs(cache)
```

## Arguments

- cache:

  A `StudyCache`, bound as the source for
  [`tracing()`](https://shah-in-boots.github.io/gram/reference/tracing.md).

## Value

An environment.

## See also

Other grammar:
[`eval_tracing()`](https://shah-in-boots.github.io/gram/reference/eval_tracing.md)
