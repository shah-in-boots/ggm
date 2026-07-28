# Render a tracing as an animated SVG widget

Compiles the tracing with
[`tracing_spec()`](https://shah-in-boots.github.io/gram/reference/tracing_spec.md)
and hands the markup and the timeline to the browser. The animation's
last frame is the composition at rest, so the same widget paused at the
end is the print still.

## Usage

``` r
gram_tracing(
  x,
  autoplay = TRUE,
  controls = TRUE,
  width = NULL,
  height = NULL,
  elementId = NULL
)
```

## Arguments

- x:

  A `Tracing`.

- autoplay:

  Whether the timeline runs on load.

- controls:

  Whether play, pause, and restart buttons are shown.

- width, height:

  Optional widget dimensions.

- elementId:

  Optional HTML element id.

## Value

An `htmlwidget`.

## See also

Other tracing:
[`at()`](https://shah-in-boots.github.io/gram/reference/at.md),
[`tracing()`](https://shah-in-boots.github.io/gram/reference/tracing.md),
[`tracing_spec()`](https://shah-in-boots.github.io/gram/reference/tracing_spec.md)
