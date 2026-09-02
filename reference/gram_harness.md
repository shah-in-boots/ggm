# Launch the development harness

Opens a page with three panels: the uPlot viewer over a fixed window, a
scripting panel for the tracing grammar, and the compiled tracing.
Scripts are evaluated by
[`eval_tracing()`](https://shah-in-boots.github.io/gram/reference/eval_tracing.md),
not by R.

## Usage

``` r
gram_harness(
  cache,
  begin = "00:00:00",
  interval = "1200 ms",
  channels = NULL,
  script = harnessScript,
  ...
)
```

## Arguments

- cache:

  A `StudyCache` from
  [`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md).

- begin, interval:

  Window shown in the viewer panel.

- channels:

  Channels loaded into the viewer panel. Defaults to every channel in
  the header.

- script:

  Initial contents of the scripting panel.

- ...:

  Passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html).

## Value

A Shiny app object.
