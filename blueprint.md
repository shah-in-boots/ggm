# ggm: Grammar of Electrograms — Design Blueprint

> A working document. This is our shared workspace, not a finished spec.
> Every section is meant to be edited, argued with, and checked off.
> Decisions get recorded in §9 so we never re-litigate them by accident.

------------------------------------------------------------------------

## 0. How we use this document

**Status legend** — put one of these at the top of any subsection as we
work:

- `OPEN` — not yet discussed / undecided
- `DECIDED` — we’ve agreed on the approach (record it in §9)
- `TODO` — agreed, not started
- `WIP` — actively being built
- `DONE` — shipped and tested

**Working style.** We tackle this in vertical slices, not horizontal
layers — each milestone (§8) should produce something runnable, even if
narrow. When we pick up a slice, we drill into its subsection here,
sketch the interface *first*, then implement. Interface before
implementation, always.

**Decision points.** Anywhere you see 🔵 **DECISION NEEDED**, that’s a
fork I want your call on before I build past it.

------------------------------------------------------------------------

## 1. Vision

`ggm` (Grammar of Electrograms) is an R package for *exploring,
annotating, and presenting* cardiac electrophysiology signal data. It is
the visualization and interaction layer; **`EGM` is the data backend**
(WFDB-compatible I/O, `signal_table`, `header_table`,
`annotation_table`, native cpp11 readers). `ggm` depends on `EGM` and
never re-implements what `EGM` already does well.

### The core insight

This is **not** three coequal features. It is **two rendering engines
joined by one annotation layer**:

                        ┌─────────────────────────────┐
                        │   annotation_table (EGM)    │  ← the connective tissue
                        │   keyed by sample + channel │
                        └──────────────┬──────────────┘
                                       │
              ┌────────────────────────┴────────────────────────┐
              │                                                  │
      ┌───────▼────────┐                              ┌──────────▼─────────┐
      │ INTERACTIVE     │                              │ PRESENTATION        │
      │ engine (canvas) │                              │ engine (vector)     │
      │  - viewing      │                              │  - the grammar      │
      │  - annotation   │                              │  - animation        │
      │  uPlot          │                              │  svg + GSAP         │
      └─────────────────┘                              └────────────────────┘
           fast, live                                    beautiful, scripted

Viewing **finds** features. Annotation mode **refines** them.
Presentation mode **animates over** them. The same `A`/`H` rows you edit
in annotation mode become the nouns the animation grammar references.
That through-line is what keeps this from being three bolted-together
apps.

### Non-goals (for now)

- Not a real-time acquisition tool — we work with exported studies.
- Not an automated diagnostician — detection algorithms live in `EGM`;
  `ggm` visualizes and lets humans correct their output.
- Presentation animation is **author-driven**, not automatic. The user
  scripts what to emphasize and how to sequence it.

### Intent, in miniature

Small examples of what each mode should *feel* like. These are our
litmus tests — if the built thing doesn’t make these feel natural, we
built the wrong thing.

**Look (viewing).** Open a multi-hour study and land on something fast:

``` r

study <- open_study("svt-case", "~/studies")
browse(study, filter = type == "VStim")   # jump straight to the pacing trains
```

**Fix (annotation).** A His detector misfired on one beat. Correct it on
that channel alone, in the same window, and save without clobbering the
algorithm:

``` r

# click the HIS D panel near the true potential → snaps to the deflection
# drag / delete / reclassify → writes <record>.hisr, leaving <record>.his intact
```

**Tell (presentation).** Take one tracing window and narrate it — the
running example for the whole §5 design, ventricular overdrive pacing
during SVT:

``` r

ggm(study, channels = c("HRA", "HIS D", "HIS M", "RV")) |>
  scene(window = c(12.4, 16.0)) |>
  reveal(channels = everything()) |>            # pen-draw the strip
  arrow(from = V_stim[last], to = A[1]) |>      # "this paced V drove this A"
  arrow(from = A[1], to = A[2]) |>              # ...and a SECOND A follows
  emphasize(pattern = "VAAV", label = "VAAV → favors AT") |>
  measure(VA[1], HV[1])                         # land on the polished, captioned frame
```

The last frame of that animation — calipers drawn, intervals labelled —
**is** the still you drop into a print slide set. Same composition,
stopped at the end. This still-equals-final-frame idea is the spine of
§5.

------------------------------------------------------------------------

## 2. System architecture

### The layers

    ┌─────────────────────────────────────────────────────────────┐
    │ L4  RENDERERS                                                 │
    │     uPlot htmlwidget (live)    │          svg + GSAP          │
    ├─────────────────────────────────────────────────────────────┤
    │ L3  GRAMMAR + APP                                             │
    │     scene spec / verbs  │  Shiny modules / mode controller    │
    ├─────────────────────────────────────────────────────────────┤
    │ L2  DATA ACCESS API (R)                                       │
    │     windowed reads · pyramid tier selection · annotation qry  │
    ├─────────────────────────────────────────────────────────────┤
    │ L1  INDEX / CACHE  (derived, regenerable)                     │
    │     signal pyramid · event pyramid · annotation index        │
    ├─────────────────────────────────────────────────────────────┤
    │ L0  CANONICAL STORAGE  (EGM)                                  │
    │     WFDB .dat/.hea (byte-seek reads)  ·  annotation files     │
    └─────────────────────────────────────────────────────────────┘

### Why these backends

| Backend | Role | Why this and not X |
|----|----|----|
| **WFDB binary** (EGM/cpp11) | canonical signal store | byte-seek range reads beat Parquet for raw signal — no columnar overhead, you hit exactly the bytes you want |
| **Signal + event pyramids** (Parquet) | multi-res signal overview + navigation map | overview is what WFDB can’t give cheaply; both store *derived* data only — LTTB-reduced signal and aggregated annotation spans — never raw samples |
| **DuckDB** (optional, over pyramid) | analytical queries on coarse data | fast range filters + `dbplyr` ergonomics if/when we want them |
| **uPlot** (htmlwidget) | interactive canvas | smallest/fastest TS renderer; canvas handles millions of pts; `sync` API for multi-panel |
| **SVG + GSAP** | presentation (sole engine) | scene-graph in one coordinate space; cross-panel arrows = single path elements; native arrowheads; subplots + animation in the same space; exports to PDF for print |
| **annotation_table** (EGM) | feature layer | already sample+channel keyed; already round-trips to WFDB |

------------------------------------------------------------------------

## 3. The data backend — **foundation, build first**

> This is the unlock. Everything in L3/L4 assumes it. It is the one
> piece that doesn’t exist yet.

### 3.0 Foundational principle — sample index is the key, time is the display

One rule the entire data layer obeys, stated once so every later section
can assume it:

> **Sample index (integer) is the canonical key for storage,
> computation, and joins. Time (seconds) is the presentation unit.**

They are never in tension, because the conversion is exact and free:

    time   = sample / sampling_frequency        # sampling_frequency from the .hea header
    sample = round(time * sampling_frequency)

**Why integer samples as the key:** - Exact — no floating-point drift
accumulating across tens of millions of samples. - Clean joins — pyramid
tiers, annotation files, and `.dat` offsets all key on the same integer;
no fuzzy time-matching. - WFDB-native — annotations already store
`sample`; the `.dat` offset *is* `sample × frame_bytes`.

**Why time for display:** - We think in *when* — “the pacing train at
4:32,” “scroll to 12.4 s.” - Every user-facing surface speaks seconds:
axis labels, the scroll target, “jump to next event,” annotation event
times, `scene(window = c(12.4, 16.0))`.

**Where the boundary sits:** the data-access API (§3.4) takes **time**
arguments from the UI, converts to a **sample** range internally, does
all work in samples, and hands back data carrying *both* (sample for the
renderer’s joins, time for its axis). Convertible either direction at
any point — fully flexible. (See D-8.)

### 3.1 Canonical storage — `DONE` (lives in EGM)

`EGM::read_signal(record, begin, end, channels, units)` already does
windowed byte-seek reads through the cpp11 layer. `ggm` calls this; it
does not duplicate it.

### 3.2 The signal pyramid — `TODO` ⭐ priority

**What it is, and what it is not.** The `.dat` stays on disk and we read
only the window we need from it (byte-seek). The pyramid does **not**
duplicate those samples. It stores the *downsampled overview* — the
thing `.dat` can’t give cheaply. The `.dat` is great at “channels 1–4,
12.4–16.0 s” (seek to the offset); it is terrible at “all 6 hours of
channel 1 at once” (read ~21M samples, discard 99.9%). The pyramid is
the precomputed answer to the second question. **Two stores, two jobs —
never the same samples in both.**

On first open, compute **LTTB** (Largest Triangle Three Buckets)
downsamples at several zoom tiers, per channel, and cache them in a
Parquet sidecar.

- **Why LTTB:** preserves the *shape* (peaks, sharp deflections) at a
  tiny fraction of points. A multi-hour trace stays recognizable at a
  few thousand points. Critical for electrograms where the morphology
  *is* the information.
- **Tiers:** ~1:10, 1:100, 1:1000, 1:10000 buckets. (Full resolution is
  *not* a tier — that’s the `.dat` itself.) We pick the tier where
  points-per-pixel ≈ 1.
- **Storage:** Parquet, partitioned by `(channel, tier)`. (D-2 decided.)
- **Size:** small. A 1 GB record yields a few MB of tiers — coarse
  levels are tiny, and even the finest overview tier is a fraction of
  the raw data.
- **Regenerable:** sidecar lives next to the record; deletable; rebuilt
  on demand by `build_pyramid()`. Never on the canonical data path.

**What actually lives in the Parquet sidecar:**

- **Downsample tiers** (the bulk) — for each `(channel, tier)`: a sample
  index (or time) + the LTTB-reduced signal value.
- **A tier manifest** — “tier T = N samples/bucket; use when
  points-per-pixel exceeds X.” This is what `get_window()` consults to
  choose a tier.
- **Optional per-bucket min/max envelopes** alongside the LTTB points —
  so at extreme zoom-out we can shade the signal’s range and never
  visually drop a sharp spike. Cheap insurance where a missed deflection
  matters.

**What is *not* here:** full-resolution signal (stays in `.dat`) and
annotations (stay in WFDB annotation files, per D-1). Parquet is purely
the derived, regenerable overview.

Proposed interface:

``` r

build_pyramid(record, record_dir = ".",
              tiers = c(10, 100, 1000, 10000),
              envelope = TRUE)     # also store per-bucket min/max
# writes  <record>.ggm-pyramid/  (Parquet) alongside the .dat/.hea
```

**Signal pyramid — Parquet schema (technical requirement).** One
partition per `(channel, tier)`:

    <record>.ggm-pyramid/signal/channel=<id>/tier=<N>/part.parquet

| Column   | Type   | Meaning                                         |
|----------|--------|-------------------------------------------------|
| `sample` | int64  | representative sample index of the LTTB point   |
| `value`  | double | LTTB-selected signal value (physical units, mV) |
| `vmin`   | double | bucket minimum — only if `envelope = TRUE`      |
| `vmax`   | double | bucket maximum — only if `envelope = TRUE`      |

Plus one manifest, `<record>.ggm-pyramid/manifest.json`:

| Field | Meaning |
|----|----|
| `sampling_frequency` | from `.hea`; the single number that converts sample↔︎time (§3.0) |
| `n_samples` | total samples per channel (study length) |
| `units` | physical unit of `value` (e.g. `"mV"`) |
| `channels[]` | channel `id` ↔︎ `label` map (mirrors header) |
| `tiers[]` | per tier: `id`, `samples_per_bucket`, `n_points`, `use_when_ppp_above` |

`use_when_ppp_above` is the points-per-pixel threshold the router (§3.4)
compares against to choose a tier.

### 3.3 Annotation handling — index + event pyramid — `TODO`

Two distinct derived structures, both built from WFDB annotation files
(which stay the on-disk source of truth, per D-1). Neither stores
signal.

**3.3a — In-memory annotation index.** A keyed `data.table` view over
the `annotation_table`, built on study load, so type/channel filters and
“jump to next AVB” are instant. A few lines, not a new on-disk store.
Keyed on `(sample, channel, type)`.

**3.3b — The event pyramid (the zoomed-out navigation map).** The new
idea, and a *second pyramid beside the signal pyramid*. At six hours on
screen the signal is barely legible no matter how good LTTB is — but the
*structure* is exactly what you navigate by: where are the pacing
trains, the long pause, the bookmarks. So the overview is **two
layers**: a faint downsampled signal for context (from §3.2) and a
**sharp annotation layer on top** that stays legible at any zoom because
it draws events, not waveform. At full-study zoom the annotations carry
*more* navigational information than the trace does.

The subtlety: at full-study zoom, individual events must **aggregate**
or they smear into noise. A pacing train is hundreds of stimuli that
should read as *one labelled band*, not hundreds of overlapping ticks.
So the event pyramid does its own density reduction — different in kind
from LTTB:

- **Runs of same-type events collapse into spans** (a pacing train → one
  `start..end` band with a count).
- **Sparse events bin by density** (coarse tiers show “12 PVCs here,”
  not 12 invisible ticks).
- **Individual marks resolve only on zoom-in** past a tier threshold.

Cheap (annotations are tiny next to signal) and regenerable from the
annotation files.

**Render contract for the overview layer:** - pacing trains / runs →
shaded spans with label + count - isolated events → ticks - bookmarks →
flags - composes with the filter model:
`browse(study, overview = type == "PaceTrain")` highlights exactly those
bands.

**Event pyramid — Parquet schema (technical requirement).** One
partition per tier:

    <record>.ggm-pyramid/events/tier=<N>/part.parquet

| Column | Type | Meaning |
|----|----|----|
| `type` | string | annotation type (e.g. `"PaceTrain"`, `"PVC"`, `"Bookmark"`) |
| `channel` | int | channel id (`0` = global) |
| `start_sample` | int64 | span start (`== end_sample` for a point event) |
| `end_sample` | int64 | span end |
| `count` | int | events aggregated into this row (`1` = individual) |
| `summary` | string | optional band label (e.g. `"S1 600ms ×8"`) |

> **The pacing-train detector is deferred (later milestone), and the
> architecture already allows it.** A detector is just an annotator: it
> writes a candidate annotation file `<record>.train` (the
> candidate-annotator pattern from §4.4). The event pyramid consumes it
> like any other annotator; nothing downstream needs to know *how* the
> spans were found. Detection plugs in later without touching the
> viewer.

### 3.4 R data-access API — `TODO`

The clean surface L3/L4 sit on. Sketch:

``` r

study <- open_study(record, record_dir)   # binds signal + header + anns + both pyramids

# All time arguments are SECONDS; converted to samples internally via fs (§3.0).
get_window(study, channels, begin, end,    # ROUTER. begin/end in seconds.
           px_width)                        #   1. samples = time * fs
                                            #   2. ppp = (end-begin)*fs / px_width
                                            #   3. ppp high -> read Parquet signal tier
                                            #      ppp ~ 1   -> EGM .dat range read
get_overview(study, channels,              # whole-study map: faint signal tier
             filter = NULL)                  #   + event-pyramid spans/ticks (§3.3b)
get_annotations(study, range = NULL,        # filtered annotation query
                filter = NULL)              #   e.g. filter = type == "AVB"
```

**`get_window()` return contract (technical requirement).** A list
containing: `sample` (int vector), `time` (double vector,
`= sample / fs`), one numeric vector per requested channel (named by
label), `tier` (which tier served it, or `"raw"` for a `.dat` read), and
— when envelopes exist — `vmin`/`vmax` per channel for shading. Carrying
both `sample` and `time` *is* the §3.0 boundary in practice: the
renderer joins annotations on `sample` and labels its axis in `time`.

**Open questions** - Does `open_study()` eagerly build the pyramid, or
lazily on first overview request with a progress bar? (Leaning lazy +
cached.) - Memory ceiling: do we ever hold full-res in memory, or always
stream windows? (Leaning always-stream; full-res only for the visible
window.)

### 3.5 How signal data reaches uPlot — `DECIDED`

Worth stating plainly, because it dissolves a natural worry: **WFDB and
uPlot never touch.** WFDB’s efficiency is purely on-disk (byte layout,
seek reads). By the time data reaches uPlot it has already passed
through EGM’s reader into R vectors and been serialized to the browser.
Storage format and renderer are fully decoupled — so **the on-disk
format (D-2: Parquet) has zero effect on uPlot**, because the browser
only ever sees post-transform data.

The path is favorable, for two reasons:

1.  **uPlot wants columnar input** — one array per series + an x array —
    and `signal_table`/`data.table` is *already* columnar (one column
    per channel). The transform is “list of columns,” no reshaping.
2.  **The pyramid means we never ship full-res.** Overview = a few
    thousand LTTB points; a zoomed window = bounded (seconds × rate ×
    channels). Both payloads are small enough that **plain JSON
    transport is fine**. Binary transport (ArrayBuffers,
    Arrow-over-wire) is only needed if you try to send raw full-res —
    which the pyramid means you never do.

**So what M0 actually validates is serialization throughput** (disk →
columnar list → wire), not “WFDB↔︎uPlot compatibility” — because that
pairing doesn’t exist.

------------------------------------------------------------------------

## 4. Interactive engine — viewing + annotation

> One canvas, two modes layered on it. Built on a multi-panel synced
> uPlot.

### 4.1 Multi-panel synced display — `DONE (M1)`

For 12–20 channels on a shared time scale: **N separate uPlot instances
linked by uPlot’s `sync` API**, *not* one chart with 20 y-axes. Sync
binds x-range, cursor, and zoom/pan across every panel in lockstep. The
vertical caliper lines up across panels for free. Add/remove a channel =
add/remove an instance.

### 4.2 Sweep speed & zoom — `TODO`

Sweep speed is just an x-range setter. Preset buttons for standard EP
speeds (25 / 50 / 100 / 200 mm/s) + free wheel-zoom, all funneling
through `uPlot.setScale('x', {min, max})`. Visible window in seconds =
`sweep_speed × viewport_width_mm`.

### 4.3 Resolution transitions — `TODO`

Watch uPlot’s `hooks.setScale`; on zoom, compute points-per-pixel, pick
the pyramid tier (via the manifest’s `use_when_ppp_above`), call
`setData()`. Swap is invisible. At extreme zoom-out, switch to the
**two-layer overview** (§3.3b): a faint downsampled signal for context
plus the sharp event layer on top — shaded spans for pacing trains/runs,
ticks for isolated events, flags for bookmarks. You navigate by
structure, not by squinting at millivolts. uPlot is stateless about
series count — “1 series” → “14 series” is fine.

### 4.4 Annotation editing — `TODO` (most subtle part)

Channel attribution is **implicit in which panel was clicked** — no
“which channel?” prompt. A draw plugin keys markers off the `channel`
column: channel-specific annotations draw only on their panel; global
markers (`channel = 0`, WFDB default) draw across all.

Verbs: - click empty → add - click near marker → select - drag → move
(rewrites `sample`) - delete / right-click → remove - double-click /
context menu → reclassify (`type` / `subtype`)

`uPlot.posToVal` converts pixel → sample; hit-test within a few px.

**Build early: snap-to-peak.** His potentials are sharp and fast —
clicking the exact 1 ms sample is maddening. Click *roughly*, snap to
local extremum (or max \|derivative\|) within ±N ms. ~10 lines; turns
correction from fiddly to fast.

**State pattern (Shiny):** optimistic local update + R as source of
truth. JS updates the marker immediately (feels instant), fires
`Shiny.setInputValue`, R updates a `reactiveVal` holding the working
`annotation_table` and pushes confirmed state back.

**Write-back — important, don’t overwrite in place.** Keep the
detector’s output as an immutable candidate annotator (`<record>.his`);
write human-corrected versions to a derived annotator (`<record>.hisr`).
WFDB encodes provenance as *file extension*, so
`EGM::write_annotation(annotator = ...)` gives this for free. Benefits:
always diffable (algorithm vs corrected), and the corrections *are* the
labeled ground truth for later detector tuning.

*Possible extension:* a parameter panel that re-runs the detector on
just the visible window so you tweak a threshold and preview candidates
before committing. Core path is manual edit; this is a stretch.

### 4.5 GUI chrome — `TODO`

Honest tradeoff: **uPlot is just the canvas.** Buttons, channel
selector, filter panel, bookmark sidebar, sweep control — we build all
of it. That’s the price of getting an EP-specific UI instead of a
generic charting one. Plain HTML/CSS + thin JS (or Alpine.js for
reactivity without a framework); wrap in a Shiny module for R-side state
(bookmarks, filters, annotation jumps).

✅ **DECIDED (D-3) — htmlwidget-first.** The renderer is an htmlwidget
(`view_signal()`), usable standalone and embeddable in Shiny via its
output/render pair with no rewrite. GUI chrome is still M5.

------------------------------------------------------------------------

## 5. Presentation engine — the grammar of electrograms

> The organizing principle, and the thing that makes this tractable:
> **the polished still IS the terminal frame of the animation.** You
> script a reveal — stim fires, an arrow shoots to the retrograde A, the
> response unfolds — and the final frame it lands on, with calipers and
> interval labels, is exactly what you export to a print slide set. One
> composition, viewed at different points on a timeline. We do **not**
> build a static renderer and an animation renderer and then fight to
> keep them matched. We build one composition; “still” just means stop
> at the end and export to vector.

Inspired by manim (a scene graph choreographed on a timeline) and ggplot
(layered, data-bound aesthetic mappings). The synthesis: **graphical
marks are bound to data features, and the timeline animates them.**

### 5.0 Why faceted ggplot is retired here — `DECIDED`

The motivating case is a cross-channel arrow: ventricular overdrive
pacing in SVT, drawing from the RV stim up to the retrograde A (or His),
then following the return sequence. That arrow crosses panels — and
**faceted ggplot cannot draw across coordinate systems, even in a
still.** EGM’s `ggm()` uses `facet_wrap(~label)`; facets are isolated
coordinate spaces. So facets break the figure whether or not it moves.
This is *the* fork that makes presentation its own renderer rather than
a thin skin over `ggm()`. (See §9 D-5.)

**The layout instead: a single coordinate space**, channels stacked by
additive vertical offset — the way EP figures are actually drawn by
hand. In that space x comes from time and y from (channel offset +
deflection height), so an arrow from *any* deflection to *any* other is
one path element with two endpoints. Cross-panel or not, it’s trivial.

### 5.1 The grammar — `OPEN` (design here together)

**Nouns** (all resolvable from the `annotation_table` + header):
channels · beats · deflections (`A`, `H`, `V`, `V_stim`, …) · intervals
(`AH`, `HV`, `VA`, …)

**Verbs:** - `reveal` / `draw` — pen-draw the trace (manim’s *Create*) -
`arrow` — draw a marked path from one deflection to another; **endpoints
are data features, not pixels** (`arrow(from = V[1], to = A[1])`). The
compiler resolves each to its sample + channel and computes (x, y) in
the shared space. - `emphasize` — highlight a beat / deflection /
detected pattern - `measure` — caliper across an interval (animated
stretch, or static on the final frame) - `transform` — morph one beat’s
measurement into the next - `focus` / `sweep` — move or scale the
viewport - `track` — build a derived subplot alongside (e.g. AH vs
S1S2), rendered as SVG in the same coordinate space; points enter over
the timeline

The `arrow` verb is the heart of it. Each arrow is an *interpretation
you are asserting as a teacher* — “this paced V drove this A” — layered
on top of the detected deflections. The annotations are the facts; the
arrows are the clinical narrative. (Your
separation-of-detection-from-interpretation principle, again.)

**Composition:** ordering from the pipe; concurrency from a grouping op;
holds from `wait()`.

### 5.2 Worked example — VOP in SVT (the VAAV response)

The case that locks the design down. Ventricular overdrive pacing
entrains an SVT; on cessation, the return sequence (VAV vs VAAV) helps
separate AT from AVNRT/AVRT.

``` r

ggm(study, channels = c("HRA", "HIS D", "HIS M", "RV")) |>
  scene(window = c(12.4, 16.0)) |>
  reveal(channels = everything()) |>                # pen-draw the strip
  play(arrow(from = V_stim[last], to = A[1])) |>    # last paced V → first return A
  play(arrow(from = A[1], to = A[2])) |>            # a SECOND A follows (the tell)
  emphasize(pattern = "VAAV",
            label = "VAAV → favors atrial tachycardia") |>
  wait(1) |>
  measure(VA[1], HV[1])                             # land on the captioned still
```

Run it → an animated teaching sequence. Stop on the last frame → the
annotated figure for print. **Same object.**

### 5.3 The scene spec — `OPEN` (the stable interface)

The one durable contract: a **declarative timeline object** (`scene()`
builds it, verbs append). Each entry is a timed graphical operation
bound to data features. Everything downstream is a *compiler* over this
spec — which is exactly what lets the renderers be swapped without
rewriting the grammar.

### 5.4 The compiler — `DECIDED` (one engine)

**SVG + a timeline engine is *the* presentation engine — the only one.**
SVG is a scene graph with one coordinate space and native arrowheads
(`marker-end`), and it exports to PDF at any resolution for print. A
mature timeline engine — **GSAP** (or anime.js / Motion) — handles the
choreography (sequence, hold, pulse, stagger) and maps almost 1:1 onto
the manim model. So: we do **not** write an animation engine (GSAP is
one, and good); we do **not** write a renderer (SVG is one); what’s
custom is the thin, valuable middle — the **scene-spec → SVG/GSAP
compiler**. Bespoke grammar on a battle-tested runtime.

| Compiler | Role | Status |
|----|----|----|
| **SVG + GSAP** | the entire presentation engine — live animation *and* print-still export (terminal frame), including derived subplots from `track` | sole engine |

**No gganimate.** Earlier drafts kept gganimate for one job: data-state
subplots (the `track(AH ~ S1S2)` plot building up). Dropped — that
subplot is just another SVG element, a scatter/line whose points enter
over the timeline, which GSAP animates trivially in the same coordinate
space as everything else. One engine removes a dependency, removes the
“two renderers must match” risk entirely, and keeps the
print-still-is-terminal-frame guarantee (D-6) airtight.

**Faceted ggplot is not part of presentation** (§5.0). EGM’s `ggm()`
facets are fine for the *interactive finisher* path, but the
presentation engine is SVG only.

*(Lineage note: gganimate’s grammar — `transition_*`, `enter_*`,
`view_*`, `shadow_*` — still informed our verb design, even though we
don’t use the engine.)*

### 5.5 Borrowed manim concepts — `TODO`

- **ValueTracker** — animate a *number* (an interval value ticking up).
- **Updaters** — geometry that recomputes as a tracker changes (a
  caliper that stretches continuously; an arrow whose head follows a
  moving endpoint).

Together these give fluid measurement and pointing animations almost for
free.

**Open questions** - Interval syntax: indexed deflections + named
intervals (`VA[1]`) vs explicit `span(V, A)`? (See §9 D-4.) - Deflection
indexing across beats — `A[1]`, `A[last]`, `A[each]` — needs a clear
resolution rule against the annotation index. - How much of the spec is
`+`-layerable (ggplot-like) vs pipe-only timeline?

------------------------------------------------------------------------

## 6. Modes & how they connect — `OPEN`

One persistent state object (`study` + working `annotation_table`). The
mode toggle swaps *interaction grammar + chrome*, not the underlying
data. “Send to presentation” is the snapshot handoff: pick a window in
the interactive view, hand it to `ggm()`/`scene()` **carrying its
annotations along** as the animation’s binding points.

      viewing ──select window──▶ annotation ──refine A/H──▶ presentation
         ▲                                                       │
         └───────────────── same study + annotations ───────────┘

------------------------------------------------------------------------

## 7. Package structure — `OPEN`

**Depends:** `EGM`. **Imports (likely):** `data.table`, `ggplot2`,
`htmlwidgets`, `shiny`, `arrow`. **Suspect/optional:** `duckdb`,
`Alpine`/bundled JS, `gsap` (vendored).

Proposed layout (subject to change):

    ggm/
    ├── R/
    │   ├── pyramid.R        # build_pyramid (signal tiers), tier selection (§3.2)
    │   ├── events.R         # build_event_pyramid, overview aggregation (§3.3b)
    │   ├── study.R          # open_study, get_window/overview/annotations (§3.4)
    │   ├── widget.R         # uPlot htmlwidget R binding (§4)
    │   ├── annotate.R       # editing verbs, snap-to-peak, write-back (§4.4)
    │   ├── app.R            # Shiny modules, mode controller (§6)
    │   ├── scene.R          # scene spec object (§5.3)
    │   ├── grammar.R        # verbs: reveal/arrow/measure/emphasize/... (§5.1)
    │   └── compile-svg.R    # SVG/GSAP compiler — the presentation engine (§5.4)
    ├── inst/htmlwidgets/    # uPlot (interactive) + SVG/GSAP (presentation) JS
    └── src/                 # (only if we need perf-critical LTTB in C++)

**Naming:** lowercase `ggm` is the package; verbs are imperative
(`measure`, `emphasize`); data accessors are `get_*`; constructors are
nouns (`scene`, `study`).

------------------------------------------------------------------------

## 8. Implementation roadmap — piecemeal milestones

Each milestone is a runnable vertical slice.

- **M0 — Pyramid + window read.** `build_pyramid()` writing the §3.2
  Parquet schema + manifest, and `get_window()` (the §3.4 router)
  returning the documented contract at adaptive resolution.
  *Acceptance:* against a real \>1 GB study, the manifest round-trips
  `fs`/tiers, a zoomed-out call reads a Parquet tier, a zoomed-in call
  falls through to a `.dat` range read, and both return matching
  `sample`+`time` vectors. *No UI yet — just prove the data layer is
  fast.* ⭐ **start here**
- **M1 — Static multi-panel render.** ✅ **Done** (`view_signal()`).
  Feeds `get_window()` output to a synced uPlot htmlwidget (vendored); N
  panels, one per channel, cursor + x-zoom synced; correct shared time
  scale. No editing.
- **M2 — Navigation.** Sweep-speed presets, wheel-zoom, resolution
  handoff (M0 tiers wired to `setScale`), overview/minimap.
- **M2.5 — Annotated overview (navigation map).** Build the event
  pyramid (§3.3b) and render the zoomed-out two-layer map: faint
  signal + event spans/ticks/flags. Scroll-by-structure, not by
  squinting. *A navigation feature that happens to consume annotations —
  independent of the editing work in M3/M4.* (§3.3b, §4.3)
- **M3 — Annotation display.** Draw plugin keyed on `channel`;
  filter/jump.
- **M4 — Annotation editing.** Add/move/delete/reclassify +
  snap-to-peak + write-back to derived annotator.
- **M5 — Shiny shell.** Chrome, sidebar, mode toggle, persistent state.
- **M6 — Scene spec + single-coordinate SVG layout.** The stable
  timeline object
  - channels stacked by vertical offset in one coordinate space. Render
    a static composition (reveal + calipers + interval labels) → export
    to PDF. *This is the print-still path and the foundation for
    animation.* (§5.0–5.4) ⭐ presentation keystone
- **M7 — SVG/GSAP animation + the `arrow` verb.** Choreograph the
  VOP/VAAV worked example end-to-end; verify the terminal frame equals
  the M6 still. (§5.2, §5.4)
- **M8 — `track` subplots in SVG.** Data-state subplots
  (e.g. `track(AH ~ S1S2)`) rendered as SVG elements whose points enter
  over the timeline, composited in the scene’s coordinate space. (§5.4)

Dependencies: M0 → everything. M1–M5 are the interactive engine. M6–M8
are the presentation engine; **M6 is the keystone** (scene spec + SVG
still), M7 adds motion, M8 is the subplot extra. M6 can begin in
parallel with M3–M5 once M0/M1 exist.

------------------------------------------------------------------------

## 9. Decision log (ADRs)

> Record every settled decision here with a one-line rationale so we
> don’t reopen it by accident. Add new ones as `D-N`.

- **D-1 `DECIDED`** — WFDB binary stays canonical; pyramid is a
  *derived* sidecar. *Rationale:* byte-seek reads beat columnar for raw
  signal; overview is the only gap, and it’s regenerable.
- **D-2 `DECIDED`** — Pyramid storage is **Parquet**, partitioned by
  `(channel, tier)`. *Rationale:* Arrow ecosystem + optional DuckDB
  queries over coarse data + clean partitioning. Stores only derived
  downsample tiers (+ manifest, + optional min/max envelopes), never raw
  `.dat` samples. Renderer- independent — uPlot never sees the on-disk
  format (§3.5).
- **D-3 `DECIDED`** — Interactive UI: **htmlwidget-first** (chosen). The
  renderer (`view_signal()`) is an htmlwidget — usable standalone
  (RMarkdown, Quarto, plain
  18. *and* the substrate Shiny renders, embeddable later via its
      auto-generated output/render pair with no rewrite (and the JS↔︎R
      channel M4 editing needs). The Shiny-module-first path was
      rejected: it would confine the renderer to a running app, losing
      the console/Quarto/print-export reach the presentation engine
      wants.
- **D-4 `OPEN`** — Interval syntax in the grammar: indexed `VA[1]` vs
  `span(V, A)`.
- **D-5 `DECIDED`** — Presentation layout is a **single coordinate
  space** (channels stacked by vertical offset), **not** faceted ggplot.
  *Rationale:* cross-channel arrows (V→A) can’t be drawn across facets
  even in a still; the motivating VOP/SVT figure requires it.
- **D-6 `DECIDED`** — **The print still is the terminal frame of the
  animation.** One composition, exported to vector at timeline end.
  *Rationale:* eliminates a whole class of static-vs-animated mismatch;
  the polished slide and the teaching reveal are the same object.
- **D-7 `DECIDED`** — **SVG + GSAP is the *sole* presentation engine.**
  gganimate is dropped — its one job (data-state subplots) is just
  another SVG element; faceted ggplot is not part of presentation.
  *Rationale:* §5.0/§5.4 — facets can’t do cross-panel marks; GSAP
  already is a timeline engine; one engine removes a dependency and the
  two-renderers-must-match risk, keeping print-still = terminal-frame
  (D-6) airtight. *(Supersedes the earlier “gganimate demoted” form.)*
- **D-8 `DECIDED`** — **Sample index (integer) is the canonical key;
  time (seconds) is the display unit.** Conversion via `fs` from the
  header is exact; the data-access API takes time, computes in samples,
  returns both. *Rationale:* exactness + clean joins to
  `.dat`/annotations + WFDB-native, while matching how users think (in
  *when*). (§3.0)
- **D-9 `DECIDED`** — The zoomed-out overview is **two layers**: faint
  signal (signal pyramid) + a sharp **event pyramid** that aggregates
  annotations (runs→spans, sparse→density bins, individual marks on
  zoom-in). Detectors that populate it (e.g. pacing-train) are deferred
  and arrive as candidate annotators (`<record>.train`) — no viewer
  changes needed. (§3.3b)

------------------------------------------------------------------------

## 10. Open questions parking lot

- Sampling frequencies / channel counts we must support at the high end?
  (Sets the perf bar for M0/M1.)
- Do studies ever span multiple WFDB records/segments we must stitch?
- Presentation export targets — just mp4/gif, or also standalone HTML
  for conference laptops with no R?
- Caliper/measurement *clinical conventions* worth encoding as defaults
  (AH, HV, paced intervals, S1S2 labeling)?
- Theming: do we inherit `EGM::theme_egm_*()` or define a
  presentation-grade theme system here?
