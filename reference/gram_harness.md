# Launch the development harness

Opens a page with three panels: the signal viewer, a scripting panel for
the tracing grammar, and the compiled tracing. Scripts are evaluated by
[`eval_tracing()`](https://shah-in-boots.github.io/gram/reference/eval_tracing.md),
not by R.

## Usage

``` r
gram_harness(
  cache,
  window = NULL,
  channels = NULL,
  backend = c("uplot", "plotly"),
  script = harnessScript,
  ...
)
```

## Arguments

- cache:

  A `StudyCache` from
  [`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md).

- window:

  Sample range the viewer opens on, as `list(begin =, end =)`. Defaults
  to the whole record.

- channels:

  Channels loaded into the viewer panel. Defaults to every channel in
  the header.

- backend:

  Renderer for the viewer panel; see
  [`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md).

- script:

  Initial contents of the scripting panel.

- ...:

  Passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html).

## Value

A Shiny app object.

## Details

The viewer opens on the whole record. At a coarse overview tier that is
the study navigator, so a reader starts by seeing the study rather than
an opening slice of it. Dragging across a panel zooms; the wheel pans;
both report the range wanted and are answered with whichever tier fits
it. The harness is the controller: it knows the backend by name only,
and every change it makes – a new window, a new tier, a different set of
channels – is one push of a fresh spec into the live widget.

## See also

Other controller:
[`gram_channels`](https://shah-in-boots.github.io/gram/reference/gram_channels.md),
[`normalize_selection()`](https://shah-in-boots.github.io/gram/reference/normalize_selection.md)
