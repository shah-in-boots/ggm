# Create an electrogram widget

`gram_plot()` is the low-level plotting primitive. It renders one panel
per signal channel so each has an independent y-scale, while
synchronising the x-range and cursor across panels. Each panel carries
its own `x` and `y`, which is what lets an overview tier draw its
per-channel extrema; panels may differ in length. The backend named in
`backend` turns the panels into what its library wants, in R, and only
that backend's assets travel with the widget. Use
[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md)
to read and display a window from a `StudyCache` directly.

## Usage

``` r
gram_plot(
  panels,
  window = NULL,
  extent = NULL,
  backend = c("uplot", "plotly"),
  scale = list(kind = "index", rate = 1),
  panel_height = 120,
  width = NULL,
  height = NULL,
  elementId = NULL
)
```

## Arguments

- panels:

  List of panels, one per channel. Each is a list holding numeric `x`
  and `y` of equal length, and optionally a `label` and a `color`.
  Lengths may differ between panels.

- window:

  Loaded range as `list(min =, max =)` in x units. Panels are drawn
  against this rather than against their own extents, so overview panels
  whose extrema fall on different samples still line up. Defaults to the
  union of the panel x extents.

- extent:

  Record range as `list(min =, max =)` in x units. Panning is clamped to
  this, so a reader may pan beyond what is loaded and have the
  controller fill it in. Defaults to `window`.

- backend:

  Renderer to draw with. Its spec is built here in R and its library is
  attached to the widget, both resolved by `gm_get_backend()`.

- scale:

  X-scale description. `kind` may be `"index"` for sample numbers,
  `"elapsed"` for elapsed seconds, or `"timestamp"` for Unix timestamps.

- panel_height:

  Height of each channel panel in CSS pixels.

- width, height:

  Optional widget dimensions.

- elementId:

  Optional HTML element id.

## Value

An `htmlwidget`.

## See also

[`view_uplot()`](https://shah-in-boots.github.io/gram/reference/view_uplot.md),
[`read_viewport()`](https://shah-in-boots.github.io/gram/reference/read_viewport.md)

Other widgets:
[`gram_plotOutput()`](https://shah-in-boots.github.io/gram/reference/gram_plotOutput.md),
[`gram_tracingOutput()`](https://shah-in-boots.github.io/gram/reference/gram_tracingOutput.md),
[`render_gram_plot()`](https://shah-in-boots.github.io/gram/reference/render_gram_plot.md),
[`render_gram_tracing()`](https://shah-in-boots.github.io/gram/reference/render_gram_tracing.md)
