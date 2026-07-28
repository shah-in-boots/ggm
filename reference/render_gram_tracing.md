# Shiny render function for a tracing

Shiny render function for a tracing

## Usage

``` r
render_gram_tracing(expr, env = parent.frame(), quoted = FALSE)
```

## Arguments

- expr:

  Expression that produces a
  [`gram_tracing()`](https://shah-in-boots.github.io/gram/reference/gram_tracing.md)
  widget.

- env:

  Environment in which to evaluate `expr`.

- quoted:

  Whether `expr` is quoted.

## Value

A Shiny render function.
