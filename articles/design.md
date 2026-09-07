# 

# Design Documentation

## Introduction

This vignette is the design plan and blueprint for the package. It is
organized into multiple developmental **arms** — the load-bearing parts
of the project. Each arm is drawn as a Mermaid flowchart box listing its
functions, sitting right above the stubs it describes.

By using this document as a developmental *blueprint*, we can quickly
see how the package was put together and the reasoning.

The set-up is that for each family of functions in the arm of the
project, we are setting up a function stubs that describe the signature
and general purpose, without having it completed. This helps to make
sure the needed components for this project are available.

The stubs are aggregated in a Mermaid diagram to serve as a visual map
of progress. If the content is blue, it currently is implemented, and if
it is orange, it is planned but not yet implemented.

### Goal

[gram](https://shah-in-boots.github.io/gram/) explores, annotates, and
presents cardiac electrophysiology studies.
[EGM](https://shah-in-boots.github.io/EGM/) owns vendor import and
WFDB-compatible signal/annotation I/O.
[gram](https://shah-in-boots.github.io/gram/) starts after normalization
to WFDB and does not duplicate the raw signal.

### Arms of the project

1.  Data Backend
2.  Visualization Engine
3.  Annotation Interaction
4.  Mark-up and Presentation

``` mermaid
%%| uses mermaid.scss preferences for the boxes so the colors can be branded
flowchart LR
    EGM["EGM + WFDB<br/>vendor import<br/>range I/O"]:::implemented
    Backend["Data Backend<br/>study handle<br/>overview cache"]:::implemented
    Viz["Visualization Engine<br/>uPlot explorer"]:::implemented
    Annot["Annotation Interaction<br/>schema; query; edit"]:::planned
    Bookmarks["Bookmarks<br/>saved view state"]:::planned
    Presentation["Mark-up and Presentation<br/>tracing grammar; anime.js; export"]:::planned

    EGM --> Backend
    Backend --> Viz
    Backend --> Annot
    Annot --> Viz
    Viz --> Bookmarks
    Bookmarks --> Presentation
    Annot --> Presentation
```

## Data Backend

``` mermaid
flowchart LR
    EGMIO["EGM I/O<br/>read_signal()<br/>read_annotation()<br/>write_annotation()"]:::implemented
    GramBackend["{gram} data backend<br/>study_cache()<br/>build_overview()<br/>read_viewport()"]:::implemented

    EGMIO --> GramBackend
```

### Study handle

The study cache or handle contains paths, header metadata, record
fingerprint, cache manifest, and annotation-layer metadata. It is
referential only, and introduces an `S7` class called `StudyCache`.

``` r

# Read header and locate sidecars; do not read the signal.
study_cache <- function(path, cache_dir = NULL, annotators = NULL, ...) {
  # implemented in R/cache.R
}

# Stream the WFDB record in fixed-size chunks and build derived tiers.
build_overview <- function(
  cache,
  chunk_seconds = 60,
  format = c("parquet", "rds"),
  rebuild = FALSE
) {
  # implemented in R/overview.R
}

# Return only the samples needed for a viewport; `window` is in samples.
read_viewport <- function(
  cache,
  window,
  channels = NULL,
  width_px = NULL,
  resolution = c("auto", "raw", "overview")
) {
  # implemented in R/overview.R
}
```

Files gram writes beside a record are named `<stem>.gram.*`, so one rule
keeps them out of annotator discovery and the package name says where
they came from. `<stem>.gram.json` is a manifest shared by every part of
gram: each writer reads it, replaces only its own section, and writes
the whole file back atomically. The cache owns the `cache` section;
bookmarks and the annotation sidecar will own sections of their own, and
a rebuild can never clobber them.

Requirements:

- Raw `.dat`/`.hea` files remain canonical and unmodified.
- Raw windows come from `EGM::read_signal(begin, end, channels)`.
- Chunk size bounds peak R memory during cache construction.
- Cache is regenerable, versioned, and invalidated by the record
  fingerprint.
- Default cache location is user-writable; read-only study directories
  must work.
- Interrupted builds are resumable or safely discarded; publish cache
  atomically.

### Overview pyramid

Initial reduction: **min/max per channel per bucket**, retaining each
extremum’s sample index and emitting the pair in time order. Advantages:
narrow spikes are not averaged away; levels can be built by merging
adjacent buckets; one streaming pass with bounded memory.

- Geometric bucket sizes, e.g. `64, 256, 1024, ...` samples.
- Choose the finest tier that returns at most about 2–4
  points/pixel/channel.
- Use raw signal once the visible range is already near screen
  resolution.
- One table, all tiers stacked, in `<stem>.gram.parquet` (rds on
  request): `level`, `start`, then `ch<i>.min`, `ch<i>.min_at`,
  `ch<i>.max`, `ch<i>.max_at` per channel position. Parquet reads a
  subset of channels without touching the rest; rds cannot.
- The `cache` section of the manifest: version, algorithm, record
  fingerprint, table file and format, units, sampling frequency, sample
  count, channels, bucket sizes, and build time. Its presence is the
  completion marker, and a fingerprint that no longer matches the record
  reads as not built.
- Never silently use an overview tier for measurement or annotation
  snapping.

`LTTB` remains a benchmark alternative, not the first implementation.
Clinical acceptance tests should compare reductions on narrow His/stim
artifacts and noisy intracardiac channels.

### Viewport return contract

- Raw: one shared `sample` array plus aligned channel arrays.
- Overview: one `sample`/`value` pair per channel; extrema differ by
  channel. Collapse a min/max pair when both refer to the same sample.
- `time` is never stored or returned; it is `sample / sample_rate`.
- Sample representation must remain exact for the supported maximum
  study size.
- `resolution`: `"raw"` or the cache bucket size.
- `request_id`: used to reject stale asynchronous responses. Not
  implemented: R is single-threaded and reads are serialised, so
  responses cannot arrive out of order until reads go asynchronous.

### Panel payload

A renderer never learns which tier it was handed. `gm_viewport_panels()`
flattens both viewport shapes into one list of panels, each carrying its
own `x` and `y` in elapsed seconds. Panels are the contract **on the R
side**: every backend starts from them. What crosses the wire is the
backend’s own spec, built in R from those panels:

``` json
{ "backend": "plotly",
  "spec":    { "...exactly what the library wants, built by gm_plotly_spec()..." },
  "window":  {"min": 12.5, "max": 22.5},
  "extent":  {"min": 0,    "max": 9787.464} }
```

`spec` is opaque to everything but the adapter of the same name.
`window` and `extent` stay top-level because two jobs need them
regardless of renderer: skipping the viewport request when the drawn
range still equals what was pushed, and clamping a pan to the record.

Panels rather than one shared x plus aligned y columns, because an
overview tier reports each channel’s extrema at the samples they fell
on. Aligning them is not merely awkward: on a 27-channel record one
window at level 4 gives per-channel counts from 2335 to 4670, 24
distinct lengths, and the only shared axis is the union of every
channel’s extrema samples — a mostly-empty grid that discards the
positions the cache exists to keep. A raw window simply hands every
panel the same `x`.

`window` is what is loaded; `extent` is the record. Panels are drawn
against `window`, not against their own extents, or each would autoscale
to a slightly different range and the stack would lose its alignment — a
bucket straddling the window edge is returned whole, so points reach
past the window by up to one bucket. Panning clamps to `extent`, so a
reader may pan past what is loaded; the canvas is briefly empty there
until the controller answers.

## Visualization Engine

``` mermaid
flowchart LR
    Viewport["read_viewport()<br/>raw and overview tiers"]:::implemented
    Panels["panels<br/>gm_viewport_panels()<br/>backend neutral, in R"]:::implemented
    Uplot["uPlot<br/>gm_uplot_spec(); view_uplot()<br/>backend-uplot.R"]:::implemented
    Plotly["plotly.js<br/>gm_plotly_spec(); view_plotly()<br/>backend-plotly.R"]:::implemented
    StudyExplorer["Study explorer<br/>explore_study()<br/>view_segment()"]:::planned

    Viewport --> Panels
    Panels --> Uplot
    Panels --> Plotly
    Uplot --> StudyExplorer
    Plotly --> StudyExplorer
```

uPlot is the canvas renderer, not the data backend. Its numeric x-scale,
`setScale()`, `setData()`, hooks, and chart synchronization fit this use
case; its input must remain viewport-sized. See the [uPlot API
documentation](https://github.com/leeoniya/uPlot/blob/master/docs/README.md).

``` r

# Read a window and return the widget. `window` is in samples, the same
# currency read_viewport() and normalize_selection() speak, so a selection made
# in the viewer feeds straight back. Defaults to the whole record, which at a
# coarse tier is the study navigator.
view_uplot <- function(cache, window = NULL, channels = NULL, width_px = 1200, ...) {
  # implemented in R/backend-uplot.R
}

# The same twelve lines with backend = "plotly"; the parallel is the point.
view_plotly <- function(cache, window = NULL, channels = NULL, width_px = 1200, ...) {
  # implemented in R/backend-plotly.R
}

# The widget and its payload; nothing here belongs to one renderer.
gram_plot <- function(panels, window = NULL, extent = NULL,
                      backend = c("uplot", "plotly"), ...) {
  # implemented in R/backend-plot.R
}

# Server-backed explorer: R services viewport and annotation requests.
explore_study <- function(study, channels = NULL, annotators = NULL, ...) {
  # TODO
}

# Standalone widget for an already-materialized window; no dynamic disk reads.
view_segment <- function(x, annotations = NULL, ...) {
  # TODO
}
```

### Swapping the renderer

The rule that decides what lives where: **JavaScript owns what happens
at interaction speed and what needs a live DOM; R owns everything that
is data.** So each backend’s translation – panels into what its library
wants – is an R function, and the JavaScript per backend shrinks to the
library call and its events. This is how [plotly](https://plotly-r.com)
and [DT](https://github.com/rstudio/DT) are built, and it puts every
choice about a figure where it can be read with
[`str()`](https://rdrr.io/r/utils/str.html).

A backend is one file on each side, named for it, holding everything
specific to it and nothing else; a file named for a role holds only what
every backend shares:

    R/backend-plot.R        gram_plot(), gm_backend() -- the register -- validators
    R/backend-viewer.R      gm_viewport_panels(): cache to panels, the seam
    R/backend-proxy.R       gm_set_data(), normalize_selection(): controller <-> live widget
    R/backend-uplot.R       gm_uplot_spec(), view_uplot()
    R/backend-plotly.R      gm_plotly_spec(), view_plotly()
    lib/gram/gram-core.js   lifecycle, emit, the set_data handler, gesture rules
    lib/gram/gram-adapter-uplot.js    drives uPlot from the spec; hooks and sync
    lib/gram/gram-adapter-plotly.js   drives Plotly.react from the spec; two events

`gm_backend(name)` returns the backend’s `spec` function and the
`htmlDependency` list its library needs;
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)
attaches only those, so a plotly widget never fetches uPlot and vice
versa. `view_<backend>()` is each backend’s troubleshooting entry: cache
and window in, that backend’s widget out, no controller. The browser
resolves `cfg.backend` through `GRAM.adapters`, and an adapter supplies
four methods:

| Method | Called when |
|----|----|
| `create(el, cfg)` | first render; `cfg.spec` is the library’s input; returns the state |
| `destroy(state)` | teardown, including a re-render of the same element |
| `resize(state)` | the element’s box changed; emit `width` only on change |
| `setData(state, spec, window)` | a controller pushed a new spec; re-force the x range; never emit |

Which channels are on screen is a controller decision, and the
controller is R: it narrows the already-loaded panels and pushes a
smaller spec. There is no `setVisible`.

The two adapters differ in the way their libraries do. uPlot is
imperative – its options carry functions – so `gm_uplot_spec()` sends
only data, labels and sizes and the adapter keeps the hooks, the sync
and the rebuild. plotly is declarative, so `gm_plotly_spec()` is the
whole figure (traces, a coupled grid, one shared x axis, every y fixed,
the gesture surface) and the adapter adds the element’s width and two
listeners. Their looks differ; that is the accepted cost of swapping,
not something to reconcile.

Navigation is one channel in the other direction. Zoom (a drag release)
and pan (the wheel) both end in a scale change, so both are reported as
the range wanted — debounced, and suppressed while a push is being
applied, since a reply would otherwise be read as a fresh request and
loop. The controller answers with whichever tier fits, so the same
gesture refines an overview into raw without the browser knowing which
it asked for.

Design:

- Shiny controller for the MWE; a static htmlwidget cannot request new R
  reads.
- One uPlot per visible channel, synchronized on x-range and cursor.
- Separate charts permit independent y-gain and channel-specific min/max
  x values.
- One controller issues a single data request for all panels.
- Keep the old tier visible while the next tier loads; discard stale
  responses.
- Debounce zoom/pan requests; later prefetch a small margin in the pan
  direction.
- Overview navigator always shows the study extent and current viewport.
- Wheel/pinch zoom around cursor; drag pan; keyboard next/previous
  window.
- Channel order, visibility, gain, grid, and polarity are view state.
- Annotations render in a plugin layer, not as dense uPlot signal
  series.

The canonical interactive control is visible duration. Conventional
sweep-speed presets map to that duration. Exact `mm/s` is only
meaningful after screen calibration; print output can use physical
dimensions exactly.

## Annotation Interaction

``` mermaid
flowchart LR
    AnnotIO["EGM annotation I/O<br/>annotation_table()<br/>read_annotation()<br/>write_annotation()"]:::implemented
    Schema["Annotation schema<br/>archetypes<br/>channel scope<br/>snap rules"]:::planned
    Review["Review and navigate<br/>query; jump<br/>add; move; save"]:::planned
    Bookmarks["Bookmarks<br/>saved view state"]:::planned

    AnnotIO --> Schema
    Schema --> Review
    Review --> Bookmarks
```

### Logical model

The UI depends on a richer logical model than a hard-coded list of QRS
symbols. The model is adapted to/from
[EGM](https://shah-in-boots.github.io/EGM/) annotation tables.

| Field | Purpose |
|----|----|
| `id` | Stable identity across edits |
| `code` | Schema-defined type: `QRS`, `A`, `H`, `V`, `stim`, … |
| `sample`, `end_sample` | Point or span in canonical coordinates |
| `channel` | Header channel id; missing/zero means study-wide |
| `source` | Imported, algorithm, user, or named annotator |
| `group_id` | Relate pulses/deflections to an episode or beat |
| `attributes` | Typed schema-defined values |

Annotation schemas are user-supplied and versioned. Each archetype
defines: code, label, point/span/group geometry, channel scope, style,
allowed attributes, and optional snap rule (`none`, peak, trough,
maximum absolute slope).

Programmed stimulation should be a span/group with child stimulus marks
and attributes such as site and coupling intervals. This supports useful
filtering; hundreds of unrelated ticks do not.

``` r

annotation_schema <- function(definition) {
  # TODO: validate and register archetypes
}

load_annotations <- function(study, annotator, schema = NULL) {
  # TODO
}

query_annotations <- function(x, window = NULL, channel = NULL,
                              code = NULL, source = NULL, ...) {
  # TODO
}

save_annotations <- function(x, annotator, overwrite = FALSE) {
  # TODO: write a new EGM/WFDB annotator atomically
}
```

Interaction requirements:

- Filter by type, channel, source, group attributes, tags, and time
  range.
- Jump next/previous; select from a result list; show event density when
  zoomed out.
- Add, select, drag, delete, and reclassify; channel inferred from
  clicked panel.
- Snapping reads raw signal around the candidate sample, never an
  overview tier.
- Optimistic browser movement; R confirms canonical sample/channel
  state.
- Undo/redo within a session; unsaved-change indicator; explicit save.
- Imported/detector annotator is immutable by default. Save review as a
  new name.
- Reopening the saved annotator reproduces the edited sample and channel
  exactly.

WFDB remains the interoperable exchange layer. If stable ids, spans,
relations, or audit metadata cannot round-trip through WFDB fields,
store them in a versioned companion sidecar rather than silently packing
semantics into `aux`. Finalize that mapping only after the intracardiac
archetypes are supplied.

### Bookmarks

A bookmark is a **saved view**, not copied signal data: record
fingerprint, sample range, channel order, gains, visible annotation
layers, label, notes, and tags. It appears in navigation like an event
and is the input to
[`tracing()`](https://shah-in-boots.github.io/gram/reference/tracing.md).

``` r

bookmark_view <- function(study, window, label = NULL, state = NULL, ...) {
  # TODO
}

list_bookmarks <- function(study, filter = NULL) {
  # TODO
}
```

## Mark-up and Presentation

``` mermaid
flowchart LR
    TracingGrammar["R tracing grammar<br/>tracing(); caliper()<br/>arrow(); emphasize(); reveal()"]:::planned
    SvgCompiler["SVG compiler<br/>one coordinate space<br/>explicit final state"]:::planned
    AnimeJs["anime.js v4<br/>timeline<br/>interpolation; playback"]:::planned
    Exports["Exports<br/>SVG; PDF<br/>HTML; later GIF/video"]:::planned

    TracingGrammar --> SvgCompiler
    SvgCompiler --> AnimeJs
    SvgCompiler --> Exports
    AnimeJs --> Exports
```

Exploration and presentation use different renderers. uPlot/canvas
prioritizes latency; short selected segments can be rendered as SVG for
precise print and cross-channel markup. Both consume the same samples,
annotations, and bookmark state.

### Grammar

Workspace for what to design for grammar. Series of examples to
organize.

- Add H to mark His
- Add point on specific channel (snap to peak)
- dV/dt marker
- arrows from one channel to another (highlight activation sequence)
- vertical square or rectangle to highlight region
- vertical stripe through entire plot

### Animation engine: anime.js

**Decision: use anime.js v4.** It is a good fit for this layer:

- MIT licensed and small enough to vendor with the htmlwidget; no CDN
  required.
- Animates SVG attributes, DOM properties, and JavaScript values.
- [`createTimeline()`](https://animejs.com/documentation/timeline/)
  supports ordered and concurrent steps, labels, timers, callbacks, and
  nested timelines.
- Playback methods provide play, pause, restart, reverse, and seek
  controls.
- [SVG helpers](https://animejs.com/documentation/svg/) support line
  drawing, motion paths, and later morphing.

Responsibility boundary:

- `gram_scene`: semantic objects, timing, and explicit final state.
- SVG compiler: traces, arrows, calipers, labels, and channel layout.
- anime.js: interpolation and timeline playback only.
- Exporter: SVG/PDF from the explicit final state; animated HTML from
  the same scene plus anime.js.

This boundary keeps the R grammar stable if the JavaScript runtime
changes. It also ensures a print still does not depend on replaying an
animation to discover where its elements finish.

| Tracing operation  | anime.js compilation         |
|--------------------|------------------------------|
| reveal trace/arrow | SVG drawable from `0` to `1` |

Vendor one pinned anime.js v4 build under `inst/htmlwidgets/lib/`. Keep
selectors, timeline positions, and anime.js option names inside the
compiler rather than in the public R object.

``` r

tracing <- function(x, ...) {
  # TODO: create from a bookmark or explicit study window; returns a tracing object
  # Creates a S7 Tracing object
}

# Example of annotation
add_marker <- function(x, from, to, label = NULL, ...) {
  # TODO
  # Generic for adding objects: arrows, dots, letters, etc
}

emphasize <- function(x, target, ...) {
  # TODO
}

render_tracing <- function(x, format = c("svg", "pdf"), ...) {
  # TODO
}

animate_tracing <- function(x, autoplay = TRUE, controls = TRUE, ...) {
  # TODO: compile the scene timeline to an anime.js-backed htmlwidget
}
```

## Introduction

This vignette is the design plan and blueprint for the package. It is
organized into multiple developmental **arms** — the load-bearing parts
of the project. Each arm is drawn as a Mermaid flowchart box listing its
functions, sitting right above the stubs it describes.

By using this document as a developmental *blueprint*, we can quickly
see how the package was put together and the reasoning.

The set-up is that for each family of functions in the arm of the
project, we are setting up a function stubs that describe the signature
and general purpose, without having it completed. This helps to make
sure the needed components for this project are available.

The stubs are aggregated in a Mermaid diagram to serve as a visual map
of progress. If the content is blue, it currently is implemented, and if
it is orange, it is planned but not yet implemented.

### Goal

[gram](https://shah-in-boots.github.io/gram/) explores, annotates, and
presents cardiac electrophysiology studies.
[EGM](https://shah-in-boots.github.io/EGM/) owns vendor import and
WFDB-compatible signal/annotation I/O.
[gram](https://shah-in-boots.github.io/gram/) starts after normalization
to WFDB and does not duplicate the raw signal.

### Arms of the project

1.  Data Backend
2.  Visualization Engine
3.  Annotation Interaction
4.  Mark-up and Presentation

``` mermaid
%%| uses mermaid.scss preferences for the boxes so the colors can be branded
flowchart LR
    EGM["EGM + WFDB<br/>vendor import<br/>range I/O"]:::implemented
    Backend["Data Backend<br/>study handle<br/>overview cache"]:::implemented
    Viz["Visualization Engine<br/>uPlot explorer"]:::implemented
    Annot["Annotation Interaction<br/>schema; query; edit"]:::planned
    Bookmarks["Bookmarks<br/>saved view state"]:::planned
    Presentation["Mark-up and Presentation<br/>tracing grammar; anime.js; export"]:::planned

    EGM --> Backend
    Backend --> Viz
    Backend --> Annot
    Annot --> Viz
    Viz --> Bookmarks
    Bookmarks --> Presentation
    Annot --> Presentation
```

## Data Backend

``` mermaid
flowchart LR
    EGMIO["EGM I/O<br/>read_signal()<br/>read_annotation()<br/>write_annotation()"]:::implemented
    GramBackend["{gram} data backend<br/>study_cache()<br/>build_overview()<br/>read_viewport()"]:::implemented

    EGMIO --> GramBackend
```

### Study handle

The study cache or handle contains paths, header metadata, record
fingerprint, cache manifest, and annotation-layer metadata. It is
referential only, and introduces an `S7` class called `StudyCache`.

``` r

# Read header and locate sidecars; do not read the signal.
study_cache <- function(path, cache_dir = NULL, annotators = NULL, ...) {
  # implemented in R/cache.R
}

# Stream the WFDB record in fixed-size chunks and build derived tiers.
build_overview <- function(
  cache,
  chunk_seconds = 60,
  format = c("parquet", "rds"),
  rebuild = FALSE
) {
  # implemented in R/overview.R
}

# Return only the samples needed for a viewport; `window` is in samples.
read_viewport <- function(
  cache,
  window,
  channels = NULL,
  width_px = NULL,
  resolution = c("auto", "raw", "overview")
) {
  # implemented in R/overview.R
}
```

Files gram writes beside a record are named `<stem>.gram.*`, so one rule
keeps them out of annotator discovery and the package name says where
they came from. `<stem>.gram.json` is a manifest shared by every part of
gram: each writer reads it, replaces only its own section, and writes
the whole file back atomically. The cache owns the `cache` section;
bookmarks and the annotation sidecar will own sections of their own, and
a rebuild can never clobber them.

Requirements:

- Raw `.dat`/`.hea` files remain canonical and unmodified.
- Raw windows come from `EGM::read_signal(begin, end, channels)`.
- Chunk size bounds peak R memory during cache construction.
- Cache is regenerable, versioned, and invalidated by the record
  fingerprint.
- Default cache location is user-writable; read-only study directories
  must work.
- Interrupted builds are resumable or safely discarded; publish cache
  atomically.

### Overview pyramid

Initial reduction: **min/max per channel per bucket**, retaining each
extremum’s sample index and emitting the pair in time order. Advantages:
narrow spikes are not averaged away; levels can be built by merging
adjacent buckets; one streaming pass with bounded memory.

- Geometric bucket sizes, e.g. `64, 256, 1024, ...` samples.
- Choose the finest tier that returns at most about 2–4
  points/pixel/channel.
- Use raw signal once the visible range is already near screen
  resolution.
- One table, all tiers stacked, in `<stem>.gram.parquet` (rds on
  request): `level`, `start`, then `ch<i>.min`, `ch<i>.min_at`,
  `ch<i>.max`, `ch<i>.max_at` per channel position. Parquet reads a
  subset of channels without touching the rest; rds cannot.
- The `cache` section of the manifest: version, algorithm, record
  fingerprint, table file and format, units, sampling frequency, sample
  count, channels, bucket sizes, and build time. Its presence is the
  completion marker, and a fingerprint that no longer matches the record
  reads as not built.
- Never silently use an overview tier for measurement or annotation
  snapping.

`LTTB` remains a benchmark alternative, not the first implementation.
Clinical acceptance tests should compare reductions on narrow His/stim
artifacts and noisy intracardiac channels.

### Viewport return contract

- Raw: one shared `sample` array plus aligned channel arrays.
- Overview: one `sample`/`value` pair per channel; extrema differ by
  channel. Collapse a min/max pair when both refer to the same sample.
- `time` is never stored or returned; it is `sample / sample_rate`.
- Sample representation must remain exact for the supported maximum
  study size.
- `resolution`: `"raw"` or the cache bucket size.
- `request_id`: used to reject stale asynchronous responses. Not
  implemented: R is single-threaded and reads are serialised, so
  responses cannot arrive out of order until reads go asynchronous.

### Panel payload

A renderer never learns which tier it was handed. `gm_viewport_panels()`
flattens both viewport shapes into one list of panels, each carrying its
own `x` and `y` in elapsed seconds. Panels are the contract **on the R
side**: every backend starts from them. What crosses the wire is the
backend’s own spec, built in R from those panels:

``` json
{ "backend": "plotly",
  "spec":    { "...exactly what the library wants, built by gm_plotly_spec()..." },
  "window":  {"min": 12.5, "max": 22.5},
  "extent":  {"min": 0,    "max": 9787.464} }
```

`spec` is opaque to everything but the adapter of the same name.
`window` and `extent` stay top-level because two jobs need them
regardless of renderer: skipping the viewport request when the drawn
range still equals what was pushed, and clamping a pan to the record.

Panels rather than one shared x plus aligned y columns, because an
overview tier reports each channel’s extrema at the samples they fell
on. Aligning them is not merely awkward: on a 27-channel record one
window at level 4 gives per-channel counts from 2335 to 4670, 24
distinct lengths, and the only shared axis is the union of every
channel’s extrema samples — a mostly-empty grid that discards the
positions the cache exists to keep. A raw window simply hands every
panel the same `x`.

`window` is what is loaded; `extent` is the record. Panels are drawn
against `window`, not against their own extents, or each would autoscale
to a slightly different range and the stack would lose its alignment — a
bucket straddling the window edge is returned whole, so points reach
past the window by up to one bucket. Panning clamps to `extent`, so a
reader may pan past what is loaded; the canvas is briefly empty there
until the controller answers.

## Visualization Engine

``` mermaid
flowchart LR
    Viewport["read_viewport()<br/>raw and overview tiers"]:::implemented
    Panels["panels<br/>gm_viewport_panels()<br/>backend neutral, in R"]:::implemented
    Uplot["uPlot<br/>gm_uplot_spec(); view_uplot()<br/>backend-uplot.R"]:::implemented
    Plotly["plotly.js<br/>gm_plotly_spec(); view_plotly()<br/>backend-plotly.R"]:::implemented
    StudyExplorer["Study explorer<br/>explore_study()<br/>view_segment()"]:::planned

    Viewport --> Panels
    Panels --> Uplot
    Panels --> Plotly
    Uplot --> StudyExplorer
    Plotly --> StudyExplorer
```

uPlot is the canvas renderer, not the data backend. Its numeric x-scale,
`setScale()`, `setData()`, hooks, and chart synchronization fit this use
case; its input must remain viewport-sized. See the [uPlot API
documentation](https://github.com/leeoniya/uPlot/blob/master/docs/README.md).

``` r

# Read a window and return the widget. `window` is in samples, the same
# currency read_viewport() and normalize_selection() speak, so a selection made
# in the viewer feeds straight back. Defaults to the whole record, which at a
# coarse tier is the study navigator.
view_uplot <- function(cache, window = NULL, channels = NULL, width_px = 1200, ...) {
  # implemented in R/backend-uplot.R
}

# The same twelve lines with backend = "plotly"; the parallel is the point.
view_plotly <- function(cache, window = NULL, channels = NULL, width_px = 1200, ...) {
  # implemented in R/backend-plotly.R
}

# The widget and its payload; nothing here belongs to one renderer.
gram_plot <- function(panels, window = NULL, extent = NULL,
                      backend = c("uplot", "plotly"), ...) {
  # implemented in R/backend-plot.R
}

# Server-backed explorer: R services viewport and annotation requests.
explore_study <- function(study, channels = NULL, annotators = NULL, ...) {
  # TODO
}

# Standalone widget for an already-materialized window; no dynamic disk reads.
view_segment <- function(x, annotations = NULL, ...) {
  # TODO
}
```

### Swapping the renderer

The rule that decides what lives where: **JavaScript owns what happens
at interaction speed and what needs a live DOM; R owns everything that
is data.** So each backend’s translation – panels into what its library
wants – is an R function, and the JavaScript per backend shrinks to the
library call and its events. This is how [plotly](https://plotly-r.com)
and [DT](https://github.com/rstudio/DT) are built, and it puts every
choice about a figure where it can be read with
[`str()`](https://rdrr.io/r/utils/str.html).

A backend is one file on each side, named for it, holding everything
specific to it and nothing else; a file named for a role holds only what
every backend shares:

    R/backend-plot.R        gram_plot(), gm_backend() -- the register -- validators
    R/backend-viewer.R      gm_viewport_panels(): cache to panels, the seam
    R/backend-proxy.R       gm_set_data(), normalize_selection(): controller <-> live widget
    R/backend-uplot.R       gm_uplot_spec(), view_uplot()
    R/backend-plotly.R      gm_plotly_spec(), view_plotly()
    lib/gram/gram-core.js   lifecycle, emit, the set_data handler, gesture rules
    lib/gram/gram-adapter-uplot.js    drives uPlot from the spec; hooks and sync
    lib/gram/gram-adapter-plotly.js   drives Plotly.react from the spec; two events

`gm_backend(name)` returns the backend’s `spec` function and the
`htmlDependency` list its library needs;
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)
attaches only those, so a plotly widget never fetches uPlot and vice
versa. `view_<backend>()` is each backend’s troubleshooting entry: cache
and window in, that backend’s widget out, no controller. The browser
resolves `cfg.backend` through `GRAM.adapters`, and an adapter supplies
four methods:

| Method | Called when |
|----|----|
| `create(el, cfg)` | first render; `cfg.spec` is the library’s input; returns the state |
| `destroy(state)` | teardown, including a re-render of the same element |
| `resize(state)` | the element’s box changed; emit `width` only on change |
| `setData(state, spec, window)` | a controller pushed a new spec; re-force the x range; never emit |

Which channels are on screen is a controller decision, and the
controller is R: it narrows the already-loaded panels and pushes a
smaller spec. There is no `setVisible`.

The two adapters differ in the way their libraries do. uPlot is
imperative – its options carry functions – so `gm_uplot_spec()` sends
only data, labels and sizes and the adapter keeps the hooks, the sync
and the rebuild. plotly is declarative, so `gm_plotly_spec()` is the
whole figure (traces, a coupled grid, one shared x axis, every y fixed,
the gesture surface) and the adapter adds the element’s width and two
listeners. Their looks differ; that is the accepted cost of swapping,
not something to reconcile.

Navigation is one channel in the other direction. Zoom (a drag release)
and pan (the wheel) both end in a scale change, so both are reported as
the range wanted — debounced, and suppressed while a push is being
applied, since a reply would otherwise be read as a fresh request and
loop. The controller answers with whichever tier fits, so the same
gesture refines an overview into raw without the browser knowing which
it asked for.

Design:

- Shiny controller for the MWE; a static htmlwidget cannot request new R
  reads.
- One uPlot per visible channel, synchronized on x-range and cursor.
- Separate charts permit independent y-gain and channel-specific min/max
  x values.
- One controller issues a single data request for all panels.
- Keep the old tier visible while the next tier loads; discard stale
  responses.
- Debounce zoom/pan requests; later prefetch a small margin in the pan
  direction.
- Overview navigator always shows the study extent and current viewport.
- Wheel/pinch zoom around cursor; drag pan; keyboard next/previous
  window.
- Channel order, visibility, gain, grid, and polarity are view state.
- Annotations render in a plugin layer, not as dense uPlot signal
  series.

The canonical interactive control is visible duration. Conventional
sweep-speed presets map to that duration. Exact `mm/s` is only
meaningful after screen calibration; print output can use physical
dimensions exactly.

## Annotation Interaction

``` mermaid
flowchart LR
    AnnotIO["EGM annotation I/O<br/>annotation_table()<br/>read_annotation()<br/>write_annotation()"]:::implemented
    Schema["Annotation schema<br/>archetypes<br/>channel scope<br/>snap rules"]:::planned
    Review["Review and navigate<br/>query; jump<br/>add; move; save"]:::planned
    Bookmarks["Bookmarks<br/>saved view state"]:::planned

    AnnotIO --> Schema
    Schema --> Review
    Review --> Bookmarks
```

### Logical model

The UI depends on a richer logical model than a hard-coded list of QRS
symbols. The model is adapted to/from
[EGM](https://shah-in-boots.github.io/EGM/) annotation tables.

| Field | Purpose |
|----|----|
| `id` | Stable identity across edits |
| `code` | Schema-defined type: `QRS`, `A`, `H`, `V`, `stim`, … |
| `sample`, `end_sample` | Point or span in canonical coordinates |
| `channel` | Header channel id; missing/zero means study-wide |
| `source` | Imported, algorithm, user, or named annotator |
| `group_id` | Relate pulses/deflections to an episode or beat |
| `attributes` | Typed schema-defined values |

Annotation schemas are user-supplied and versioned. Each archetype
defines: code, label, point/span/group geometry, channel scope, style,
allowed attributes, and optional snap rule (`none`, peak, trough,
maximum absolute slope).

Programmed stimulation should be a span/group with child stimulus marks
and attributes such as site and coupling intervals. This supports useful
filtering; hundreds of unrelated ticks do not.

``` r

annotation_schema <- function(definition) {
  # TODO: validate and register archetypes
}

load_annotations <- function(study, annotator, schema = NULL) {
  # TODO
}

query_annotations <- function(x, window = NULL, channel = NULL,
                              code = NULL, source = NULL, ...) {
  # TODO
}

save_annotations <- function(x, annotator, overwrite = FALSE) {
  # TODO: write a new EGM/WFDB annotator atomically
}
```

Interaction requirements:

- Filter by type, channel, source, group attributes, tags, and time
  range.
- Jump next/previous; select from a result list; show event density when
  zoomed out.
- Add, select, drag, delete, and reclassify; channel inferred from
  clicked panel.
- Snapping reads raw signal around the candidate sample, never an
  overview tier.
- Optimistic browser movement; R confirms canonical sample/channel
  state.
- Undo/redo within a session; unsaved-change indicator; explicit save.
- Imported/detector annotator is immutable by default. Save review as a
  new name.
- Reopening the saved annotator reproduces the edited sample and channel
  exactly.

WFDB remains the interoperable exchange layer. If stable ids, spans,
relations, or audit metadata cannot round-trip through WFDB fields,
store them in a versioned companion sidecar rather than silently packing
semantics into `aux`. Finalize that mapping only after the intracardiac
archetypes are supplied.

### Bookmarks

A bookmark is a **saved view**, not copied signal data: record
fingerprint, sample range, channel order, gains, visible annotation
layers, label, notes, and tags. It appears in navigation like an event
and is the input to
[`tracing()`](https://shah-in-boots.github.io/gram/reference/tracing.md).

``` r

bookmark_view <- function(study, window, label = NULL, state = NULL, ...) {
  # TODO
}

list_bookmarks <- function(study, filter = NULL) {
  # TODO
}
```

## Mark-up and Presentation

``` mermaid
flowchart LR
    TracingGrammar["R tracing grammar<br/>tracing(); caliper()<br/>arrow(); emphasize(); reveal()"]:::planned
    SvgCompiler["SVG compiler<br/>one coordinate space<br/>explicit final state"]:::planned
    AnimeJs["anime.js v4<br/>timeline<br/>interpolation; playback"]:::planned
    Exports["Exports<br/>SVG; PDF<br/>HTML; later GIF/video"]:::planned

    TracingGrammar --> SvgCompiler
    SvgCompiler --> AnimeJs
    SvgCompiler --> Exports
    AnimeJs --> Exports
```

Exploration and presentation use different renderers. uPlot/canvas
prioritizes latency; short selected segments can be rendered as SVG for
precise print and cross-channel markup. Both consume the same samples,
annotations, and bookmark state.

### Grammar

Workspace for what to design for grammar. Series of examples to
organize.

- Add H to mark His
- Add point on specific channel (snap to peak)
- dV/dt marker
- arrows from one channel to another (highlight activation sequence)
- vertical square or rectangle to highlight region
- vertical stripe through entire plot

### Animation engine: anime.js

**Decision: use anime.js v4.** It is a good fit for this layer:

- MIT licensed and small enough to vendor with the htmlwidget; no CDN
  required.
- Animates SVG attributes, DOM properties, and JavaScript values.
- [`createTimeline()`](https://animejs.com/documentation/timeline/)
  supports ordered and concurrent steps, labels, timers, callbacks, and
  nested timelines.
- Playback methods provide play, pause, restart, reverse, and seek
  controls.
- [SVG helpers](https://animejs.com/documentation/svg/) support line
  drawing, motion paths, and later morphing.

Responsibility boundary:

- `gram_scene`: semantic objects, timing, and explicit final state.
- SVG compiler: traces, arrows, calipers, labels, and channel layout.
- anime.js: interpolation and timeline playback only.
- Exporter: SVG/PDF from the explicit final state; animated HTML from
  the same scene plus anime.js.

This boundary keeps the R grammar stable if the JavaScript runtime
changes. It also ensures a print still does not depend on replaying an
animation to discover where its elements finish.

| Tracing operation  | anime.js compilation         |
|--------------------|------------------------------|
| reveal trace/arrow | SVG drawable from `0` to `1` |

Vendor one pinned anime.js v4 build under `inst/htmlwidgets/lib/`. Keep
selectors, timeline positions, and anime.js option names inside the
compiler rather than in the public R object.

``` r

tracing <- function(x, ...) {
  # TODO: create from a bookmark or explicit study window; returns a tracing object
  # Creates a S7 Tracing object
}

# Example of annotation
add_marker <- function(x, from, to, label = NULL, ...) {
  # TODO
  # Generic for adding objects: arrows, dots, letters, etc
}

emphasize <- function(x, target, ...) {
  # TODO
}

render_tracing <- function(x, format = c("svg", "pdf"), ...) {
  # TODO
}

animate_tracing <- function(x, autoplay = TRUE, controls = TRUE, ...) {
  # TODO: compile the scene timeline to an anime.js-backed htmlwidget
}
```

## Introduction

This vignette is the design plan and blueprint for the package. It is
organized into multiple developmental **arms** — the load-bearing parts
of the project. Each arm is drawn as a Mermaid flowchart box listing its
functions, sitting right above the stubs it describes.

By using this document as a developmental *blueprint*, we can quickly
see how the package was put together and the reasoning.

The set-up is that for each family of functions in the arm of the
project, we are setting up a function stubs that describe the signature
and general purpose, without having it completed. This helps to make
sure the needed components for this project are available.

The stubs are aggregated in a Mermaid diagram to serve as a visual map
of progress. If the content is blue, it currently is implemented, and if
it is orange, it is planned but not yet implemented.

### Goal

[gram](https://shah-in-boots.github.io/gram/) explores, annotates, and
presents cardiac electrophysiology studies.
[EGM](https://shah-in-boots.github.io/EGM/) owns vendor import and
WFDB-compatible signal/annotation I/O.
[gram](https://shah-in-boots.github.io/gram/) starts after normalization
to WFDB and does not duplicate the raw signal.

### Arms of the project

1.  Data Backend
2.  Visualization Engine
3.  Annotation Interaction
4.  Mark-up and Presentation

``` mermaid
%%| uses mermaid.scss preferences for the boxes so the colors can be branded
flowchart LR
    EGM["EGM + WFDB<br/>vendor import<br/>range I/O"]:::implemented
    Backend["Data Backend<br/>study handle<br/>overview cache"]:::implemented
    Viz["Visualization Engine<br/>uPlot explorer"]:::implemented
    Annot["Annotation Interaction<br/>schema; query; edit"]:::planned
    Bookmarks["Bookmarks<br/>saved view state"]:::planned
    Presentation["Mark-up and Presentation<br/>tracing grammar; anime.js; export"]:::planned

    EGM --> Backend
    Backend --> Viz
    Backend --> Annot
    Annot --> Viz
    Viz --> Bookmarks
    Bookmarks --> Presentation
    Annot --> Presentation
```

## Data Backend

``` mermaid
flowchart LR
    EGMIO["EGM I/O<br/>read_signal()<br/>read_annotation()<br/>write_annotation()"]:::implemented
    GramBackend["{gram} data backend<br/>study_cache()<br/>build_overview()<br/>read_viewport()"]:::implemented

    EGMIO --> GramBackend
```

### Study handle

The study cache or handle contains paths, header metadata, record
fingerprint, cache manifest, and annotation-layer metadata. It is
referential only, and introduces an `S7` class called `StudyCache`.

``` r

# Read header and locate sidecars; do not read the signal.
study_cache <- function(path, cache_dir = NULL, annotators = NULL, ...) {
  # implemented in R/cache.R
}

# Stream the WFDB record in fixed-size chunks and build derived tiers.
build_overview <- function(
  cache,
  chunk_seconds = 60,
  format = c("parquet", "rds"),
  rebuild = FALSE
) {
  # implemented in R/overview.R
}

# Return only the samples needed for a viewport; `window` is in samples.
read_viewport <- function(
  cache,
  window,
  channels = NULL,
  width_px = NULL,
  resolution = c("auto", "raw", "overview")
) {
  # implemented in R/overview.R
}
```

Files gram writes beside a record are named `<stem>.gram.*`, so one rule
keeps them out of annotator discovery and the package name says where
they came from. `<stem>.gram.json` is a manifest shared by every part of
gram: each writer reads it, replaces only its own section, and writes
the whole file back atomically. The cache owns the `cache` section;
bookmarks and the annotation sidecar will own sections of their own, and
a rebuild can never clobber them.

Requirements:

- Raw `.dat`/`.hea` files remain canonical and unmodified.
- Raw windows come from `EGM::read_signal(begin, end, channels)`.
- Chunk size bounds peak R memory during cache construction.
- Cache is regenerable, versioned, and invalidated by the record
  fingerprint.
- Default cache location is user-writable; read-only study directories
  must work.
- Interrupted builds are resumable or safely discarded; publish cache
  atomically.

### Overview pyramid

Initial reduction: **min/max per channel per bucket**, retaining each
extremum’s sample index and emitting the pair in time order. Advantages:
narrow spikes are not averaged away; levels can be built by merging
adjacent buckets; one streaming pass with bounded memory.

- Geometric bucket sizes, e.g. `64, 256, 1024, ...` samples.
- Choose the finest tier that returns at most about 2–4
  points/pixel/channel.
- Use raw signal once the visible range is already near screen
  resolution.
- One table, all tiers stacked, in `<stem>.gram.parquet` (rds on
  request): `level`, `start`, then `ch<i>.min`, `ch<i>.min_at`,
  `ch<i>.max`, `ch<i>.max_at` per channel position. Parquet reads a
  subset of channels without touching the rest; rds cannot.
- The `cache` section of the manifest: version, algorithm, record
  fingerprint, table file and format, units, sampling frequency, sample
  count, channels, bucket sizes, and build time. Its presence is the
  completion marker, and a fingerprint that no longer matches the record
  reads as not built.
- Never silently use an overview tier for measurement or annotation
  snapping.

`LTTB` remains a benchmark alternative, not the first implementation.
Clinical acceptance tests should compare reductions on narrow His/stim
artifacts and noisy intracardiac channels.

### Viewport return contract

- Raw: one shared `sample` array plus aligned channel arrays.
- Overview: one `sample`/`value` pair per channel; extrema differ by
  channel. Collapse a min/max pair when both refer to the same sample.
- `time` is never stored or returned; it is `sample / sample_rate`.
- Sample representation must remain exact for the supported maximum
  study size.
- `resolution`: `"raw"` or the cache bucket size.
- `request_id`: used to reject stale asynchronous responses. Not
  implemented: R is single-threaded and reads are serialised, so
  responses cannot arrive out of order until reads go asynchronous.

### Panel payload

A renderer never learns which tier it was handed. `gm_viewport_panels()`
flattens both viewport shapes into one list of panels, each carrying its
own `x` and `y` in elapsed seconds. Panels are the contract **on the R
side**: every backend starts from them. What crosses the wire is the
backend’s own spec, built in R from those panels:

``` json
{ "backend": "plotly",
  "spec":    { "...exactly what the library wants, built by gm_plotly_spec()..." },
  "window":  {"min": 12.5, "max": 22.5},
  "extent":  {"min": 0,    "max": 9787.464} }
```

`spec` is opaque to everything but the adapter of the same name.
`window` and `extent` stay top-level because two jobs need them
regardless of renderer: skipping the viewport request when the drawn
range still equals what was pushed, and clamping a pan to the record.

Panels rather than one shared x plus aligned y columns, because an
overview tier reports each channel’s extrema at the samples they fell
on. Aligning them is not merely awkward: on a 27-channel record one
window at level 4 gives per-channel counts from 2335 to 4670, 24
distinct lengths, and the only shared axis is the union of every
channel’s extrema samples — a mostly-empty grid that discards the
positions the cache exists to keep. A raw window simply hands every
panel the same `x`.

`window` is what is loaded; `extent` is the record. Panels are drawn
against `window`, not against their own extents, or each would autoscale
to a slightly different range and the stack would lose its alignment — a
bucket straddling the window edge is returned whole, so points reach
past the window by up to one bucket. Panning clamps to `extent`, so a
reader may pan past what is loaded; the canvas is briefly empty there
until the controller answers.

## Visualization Engine

``` mermaid
flowchart LR
    Viewport["read_viewport()<br/>raw and overview tiers"]:::implemented
    Panels["panels<br/>gm_viewport_panels()<br/>backend neutral, in R"]:::implemented
    Uplot["uPlot<br/>gm_uplot_spec(); view_uplot()<br/>backend-uplot.R"]:::implemented
    Plotly["plotly.js<br/>gm_plotly_spec(); view_plotly()<br/>backend-plotly.R"]:::implemented
    StudyExplorer["Study explorer<br/>explore_study()<br/>view_segment()"]:::planned

    Viewport --> Panels
    Panels --> Uplot
    Panels --> Plotly
    Uplot --> StudyExplorer
    Plotly --> StudyExplorer
```

uPlot is the canvas renderer, not the data backend. Its numeric x-scale,
`setScale()`, `setData()`, hooks, and chart synchronization fit this use
case; its input must remain viewport-sized. See the [uPlot API
documentation](https://github.com/leeoniya/uPlot/blob/master/docs/README.md).

``` r

# Read a window and return the widget. `window` is in samples, the same
# currency read_viewport() and normalize_selection() speak, so a selection made
# in the viewer feeds straight back. Defaults to the whole record, which at a
# coarse tier is the study navigator.
view_uplot <- function(cache, window = NULL, channels = NULL, width_px = 1200, ...) {
  # implemented in R/backend-uplot.R
}

# The same twelve lines with backend = "plotly"; the parallel is the point.
view_plotly <- function(cache, window = NULL, channels = NULL, width_px = 1200, ...) {
  # implemented in R/backend-plotly.R
}

# The widget and its payload; nothing here belongs to one renderer.
gram_plot <- function(panels, window = NULL, extent = NULL,
                      backend = c("uplot", "plotly"), ...) {
  # implemented in R/backend-plot.R
}

# Server-backed explorer: R services viewport and annotation requests.
explore_study <- function(study, channels = NULL, annotators = NULL, ...) {
  # TODO
}

# Standalone widget for an already-materialized window; no dynamic disk reads.
view_segment <- function(x, annotations = NULL, ...) {
  # TODO
}
```

### Swapping the renderer

The rule that decides what lives where: **JavaScript owns what happens
at interaction speed and what needs a live DOM; R owns everything that
is data.** So each backend’s translation – panels into what its library
wants – is an R function, and the JavaScript per backend shrinks to the
library call and its events. This is how [plotly](https://plotly-r.com)
and [DT](https://github.com/rstudio/DT) are built, and it puts every
choice about a figure where it can be read with
[`str()`](https://rdrr.io/r/utils/str.html).

A backend is one file on each side, named for it, holding everything
specific to it and nothing else; a file named for a role holds only what
every backend shares:

    R/backend-plot.R        gram_plot(), gm_backend() -- the register -- validators
    R/backend-viewer.R      gm_viewport_panels(): cache to panels, the seam
    R/backend-proxy.R       gm_set_data(), normalize_selection(): controller <-> live widget
    R/backend-uplot.R       gm_uplot_spec(), view_uplot()
    R/backend-plotly.R      gm_plotly_spec(), view_plotly()
    lib/gram/gram-core.js   lifecycle, emit, the set_data handler, gesture rules
    lib/gram/gram-adapter-uplot.js    drives uPlot from the spec; hooks and sync
    lib/gram/gram-adapter-plotly.js   drives Plotly.react from the spec; two events

`gm_backend(name)` returns the backend’s `spec` function and the
`htmlDependency` list its library needs;
[`gram_plot()`](https://shah-in-boots.github.io/gram/reference/gram_plot.md)
attaches only those, so a plotly widget never fetches uPlot and vice
versa. `view_<backend>()` is each backend’s troubleshooting entry: cache
and window in, that backend’s widget out, no controller. The browser
resolves `cfg.backend` through `GRAM.adapters`, and an adapter supplies
four methods:

| Method | Called when |
|----|----|
| `create(el, cfg)` | first render; `cfg.spec` is the library’s input; returns the state |
| `destroy(state)` | teardown, including a re-render of the same element |
| `resize(state)` | the element’s box changed; emit `width` only on change |
| `setData(state, spec, window)` | a controller pushed a new spec; re-force the x range; never emit |

Which channels are on screen is a controller decision, and the
controller is R: it narrows the already-loaded panels and pushes a
smaller spec. There is no `setVisible`.

The two adapters differ in the way their libraries do. uPlot is
imperative – its options carry functions – so `gm_uplot_spec()` sends
only data, labels and sizes and the adapter keeps the hooks, the sync
and the rebuild. plotly is declarative, so `gm_plotly_spec()` is the
whole figure (traces, a coupled grid, one shared x axis, every y fixed,
the gesture surface) and the adapter adds the element’s width and two
listeners. Their looks differ; that is the accepted cost of swapping,
not something to reconcile.

Navigation is one channel in the other direction. Zoom (a drag release)
and pan (the wheel) both end in a scale change, so both are reported as
the range wanted — debounced, and suppressed while a push is being
applied, since a reply would otherwise be read as a fresh request and
loop. The controller answers with whichever tier fits, so the same
gesture refines an overview into raw without the browser knowing which
it asked for.

Design:

- Shiny controller for the MWE; a static htmlwidget cannot request new R
  reads.
- One uPlot per visible channel, synchronized on x-range and cursor.
- Separate charts permit independent y-gain and channel-specific min/max
  x values.
- One controller issues a single data request for all panels.
- Keep the old tier visible while the next tier loads; discard stale
  responses.
- Debounce zoom/pan requests; later prefetch a small margin in the pan
  direction.
- Overview navigator always shows the study extent and current viewport.
- Wheel/pinch zoom around cursor; drag pan; keyboard next/previous
  window.
- Channel order, visibility, gain, grid, and polarity are view state.
- Annotations render in a plugin layer, not as dense uPlot signal
  series.

The canonical interactive control is visible duration. Conventional
sweep-speed presets map to that duration. Exact `mm/s` is only
meaningful after screen calibration; print output can use physical
dimensions exactly.

## Annotation Interaction

``` mermaid
flowchart LR
    AnnotIO["EGM annotation I/O<br/>annotation_table()<br/>read_annotation()<br/>write_annotation()"]:::implemented
    Schema["Annotation schema<br/>archetypes<br/>channel scope<br/>snap rules"]:::planned
    Review["Review and navigate<br/>query; jump<br/>add; move; save"]:::planned
    Bookmarks["Bookmarks<br/>saved view state"]:::planned

    AnnotIO --> Schema
    Schema --> Review
    Review --> Bookmarks
```

### Logical model

The UI depends on a richer logical model than a hard-coded list of QRS
symbols. The model is adapted to/from
[EGM](https://shah-in-boots.github.io/EGM/) annotation tables.

| Field | Purpose |
|----|----|
| `id` | Stable identity across edits |
| `code` | Schema-defined type: `QRS`, `A`, `H`, `V`, `stim`, … |
| `sample`, `end_sample` | Point or span in canonical coordinates |
| `channel` | Header channel id; missing/zero means study-wide |
| `source` | Imported, algorithm, user, or named annotator |
| `group_id` | Relate pulses/deflections to an episode or beat |
| `attributes` | Typed schema-defined values |

Annotation schemas are user-supplied and versioned. Each archetype
defines: code, label, point/span/group geometry, channel scope, style,
allowed attributes, and optional snap rule (`none`, peak, trough,
maximum absolute slope).

Programmed stimulation should be a span/group with child stimulus marks
and attributes such as site and coupling intervals. This supports useful
filtering; hundreds of unrelated ticks do not.

``` r

annotation_schema <- function(definition) {
  # TODO: validate and register archetypes
}

load_annotations <- function(study, annotator, schema = NULL) {
  # TODO
}

query_annotations <- function(x, window = NULL, channel = NULL,
                              code = NULL, source = NULL, ...) {
  # TODO
}

save_annotations <- function(x, annotator, overwrite = FALSE) {
  # TODO: write a new EGM/WFDB annotator atomically
}
```

Interaction requirements:

- Filter by type, channel, source, group attributes, tags, and time
  range.
- Jump next/previous; select from a result list; show event density when
  zoomed out.
- Add, select, drag, delete, and reclassify; channel inferred from
  clicked panel.
- Snapping reads raw signal around the candidate sample, never an
  overview tier.
- Optimistic browser movement; R confirms canonical sample/channel
  state.
- Undo/redo within a session; unsaved-change indicator; explicit save.
- Imported/detector annotator is immutable by default. Save review as a
  new name.
- Reopening the saved annotator reproduces the edited sample and channel
  exactly.

WFDB remains the interoperable exchange layer. If stable ids, spans,
relations, or audit metadata cannot round-trip through WFDB fields,
store them in a versioned companion sidecar rather than silently packing
semantics into `aux`. Finalize that mapping only after the intracardiac
archetypes are supplied.

### Bookmarks

A bookmark is a **saved view**, not copied signal data: record
fingerprint, sample range, channel order, gains, visible annotation
layers, label, notes, and tags. It appears in navigation like an event
and is the input to
[`tracing()`](https://shah-in-boots.github.io/gram/reference/tracing.md).

``` r

bookmark_view <- function(study, window, label = NULL, state = NULL, ...) {
  # TODO
}

list_bookmarks <- function(study, filter = NULL) {
  # TODO
}
```

## Mark-up and Presentation

``` mermaid
flowchart LR
    TracingGrammar["R tracing grammar<br/>tracing(); caliper()<br/>arrow(); emphasize(); reveal()"]:::planned
    SvgCompiler["SVG compiler<br/>one coordinate space<br/>explicit final state"]:::planned
    AnimeJs["anime.js v4<br/>timeline<br/>interpolation; playback"]:::planned
    Exports["Exports<br/>SVG; PDF<br/>HTML; later GIF/video"]:::planned

    TracingGrammar --> SvgCompiler
    SvgCompiler --> AnimeJs
    SvgCompiler --> Exports
    AnimeJs --> Exports
```

Exploration and presentation use different renderers. uPlot/canvas
prioritizes latency; short selected segments can be rendered as SVG for
precise print and cross-channel markup. Both consume the same samples,
annotations, and bookmark state.

### Grammar

Workspace for what to design for grammar. Series of examples to
organize.

- Add H to mark His
- Add point on specific channel (snap to peak)
- dV/dt marker
- arrows from one channel to another (highlight activation sequence)
- vertical square or rectangle to highlight region
- vertical stripe through entire plot

### Animation engine: anime.js

**Decision: use anime.js v4.** It is a good fit for this layer:

- MIT licensed and small enough to vendor with the htmlwidget; no CDN
  required.
- Animates SVG attributes, DOM properties, and JavaScript values.
- [`createTimeline()`](https://animejs.com/documentation/timeline/)
  supports ordered and concurrent steps, labels, timers, callbacks, and
  nested timelines.
- Playback methods provide play, pause, restart, reverse, and seek
  controls.
- [SVG helpers](https://animejs.com/documentation/svg/) support line
  drawing, motion paths, and later morphing.

Responsibility boundary:

- `gram_scene`: semantic objects, timing, and explicit final state.
- SVG compiler: traces, arrows, calipers, labels, and channel layout.
- anime.js: interpolation and timeline playback only.
- Exporter: SVG/PDF from the explicit final state; animated HTML from
  the same scene plus anime.js.

This boundary keeps the R grammar stable if the JavaScript runtime
changes. It also ensures a print still does not depend on replaying an
animation to discover where its elements finish.

| Tracing operation  | anime.js compilation         |
|--------------------|------------------------------|
| reveal trace/arrow | SVG drawable from `0` to `1` |

Vendor one pinned anime.js v4 build under `inst/htmlwidgets/lib/`. Keep
selectors, timeline positions, and anime.js option names inside the
compiler rather than in the public R object.

``` r

tracing <- function(x, ...) {
  # TODO: create from a bookmark or explicit study window; returns a tracing object
  # Creates a S7 Tracing object
}

# Example of annotation
add_marker <- function(x, from, to, label = NULL, ...) {
  # TODO
  # Generic for adding objects: arrows, dots, letters, etc
}

emphasize <- function(x, target, ...) {
  # TODO
}

render_tracing <- function(x, format = c("svg", "pdf"), ...) {
  # TODO
}

animate_tracing <- function(x, autoplay = TRUE, controls = TRUE, ...) {
  # TODO: compile the scene timeline to an anime.js-backed htmlwidget
}
```
