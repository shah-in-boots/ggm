# Launch the development harness

Opens a page with three panels: the uPlot viewer over a fixed window, a
scripting panel for the tracing grammar, and the compiled tracing with
playback controls. The script panel runs on load, so the harness opens
with a working tracing rather than an empty stage.

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
  the header. The
  [gram_channels](https://shah-in-boots.github.io/gram/reference/gram_channels.md)
  module beside the viewer switches these on and off; because the widget
  already holds them all, that costs no further read of the record.

- script:

  Initial contents of the scripting panel.

- ...:

  Passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html).

## Value

A Shiny app object.

## Details

The panel accepts the tracing grammar only. Scripts are checked against
the verb whitelist and evaluated in the sealed environment built by
[`gram_verbs()`](https://shah-in-boots.github.io/gram/reference/gram_verbs.md),
so a script cannot reach R outside the grammar.

Dragging across the viewer reports the selected sample range above the
script state, through
[`normalize_selection()`](https://shah-in-boots.github.io/gram/reference/normalize_selection.md).
Nothing consumes that range yet – the readout exists to confirm the
browser can reach R at all.
