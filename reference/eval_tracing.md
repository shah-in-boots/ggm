# Evaluate a tracing script

Parses `text`, rejects anything outside the grammar, and evaluates the
result in the sealed environment from
[`gram_verbs()`](https://shah-in-boots.github.io/gram/reference/gram_verbs.md).

## Usage

``` r
eval_tracing(text, cache)
```

## Arguments

- text:

  A single string holding the script.

- cache:

  A `StudyCache`.

## Value

The `Tracing` the script produced.

## See also

Other grammar:
[`gram_verbs()`](https://shah-in-boots.github.io/gram/reference/gram_verbs.md)
