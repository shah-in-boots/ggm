# Shiny render function for a gram plot

Shiny render function for a gram plot

## Usage

``` r
render_gram_plot(expr, env = parent.frame(), quoted = FALSE)
```

## Arguments

- expr:

  Expression that produces a
  [`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)
  widget.

- env:

  Environment in which to evaluate `expr`.

- quoted:

  Whether `expr` is quoted.

## Value

A Shiny render function.

## See also

Other widgets:
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md),
[`gram_plotOutput()`](https://shah-in-boots.github.io/gram/reference/gram_plotOutput.md),
[`gram_tracingOutput()`](https://shah-in-boots.github.io/gram/reference/gram_tracingOutput.md),
[`render_gram_tracing()`](https://shah-in-boots.github.io/gram/reference/render_gram_tracing.md)
