# Draw an arrow between two points

The endpoints may sit on different channels; the tracing is laid out in
one coordinate space so a cross-channel arrow is a single path.

## Usage

``` r
add_arrow(x, from, to, label = NULL, duration = 600)
```

## Arguments

- x:

  A `Tracing`.

- from, to:

  Points from
  [`at()`](https://shah-in-boots.github.io/gram/reference/at.md).

- label:

  Optional text drawn at the arrow's midpoint.

- duration:

  Milliseconds for the arrow to draw.

## Value

The tracing, with the operation appended.

## See also

Other tracing verbs:
[`emphasize()`](https://shah-in-boots.github.io/gram/reference/emphasize.md),
[`reveal()`](https://shah-in-boots.github.io/gram/reference/reveal.md)
