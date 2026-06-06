# The `view_*` family — interactive visualization workflow

> Companion to `blueprint.md` §4 (Interactive engine). This note drills into the
> *viewing* slice: the R surface (`view_*`), the htmlwidget that renders it, how
> it consumes the data layer that already exists (`get_window()`), and the exact
> seam where Shiny enters. Design only — no implementation committed yet.
>
> **Status:** `WIP` design. Decisions that belong in `blueprint.md` §9 are flagged.
>
> **Settled here:** D-3 (blueprint) is resolved **htmlwidget-first** — see §7.

---

## 1. Where this sits

The blueprint frames `ggm` as *"two rendering engines joined by one annotation
layer"* (§1). This note is entirely about the **interactive engine** — the
left-hand box: *viewing* and (later) *annotation*. The presentation engine
(SVG + GSAP) is out of scope here.

The data layer it stands on is **already built** (milestone M0):

- `open_study()` → a lazy `ggm_study` (header only; signal read on demand).
- `get_window(study, channels, begin, end, px_width)` → the windowed-read
  **router**: takes a time window in seconds, works in samples, returns a
  `ggm_window` (a `data.table` with `sample`, `time`, and one column per
  channel) carrying `tier`/`ppp`/`frequency` attributes.
- `build_pyramid()` → the LTTB overview sidecar the router serves at zoom-out.

What does **not** exist yet is anything that *draws*. That is the `view_*`
family.

---

## 2. The spine: lightWAVE's client/server split is already ggm's data layer

LightWAVE (PhysioNet's lightweight WFDB waveform/annotation viewer) is built
from two cleanly separable parts:

- a **back end** — a C/CGI program that does windowed reads against WFDB records
  and returns the requested slice as JSON;
- a **front end** — a JavaScript app in the browser that lays signals out in a
  *signal window* (the scope), draws a whole-record *navigation bar* with
  annotation markers underneath, and handles scroll / zoom / go-to-time /
  search / annotation editing.

That is exactly the split `ggm` already has — only the back end is **R**, not
CGI, and the front end will be **uPlot**, not bespoke canvas code:

| lightWAVE | ggm equivalent | status |
|---|---|---|
| CGI: windowed signal fetch (`fetch` request) | `get_window(study, …, px_width)` | ✅ M0 |
| CGI: annotation fetch | `get_annotations()` | stub (M3) |
| Navigation bar (whole record + event ticks/flags) | `get_overview()` two-layer map (§3.3b) | stub (M2.5) |
| JS client: the signal scope | **uPlot htmlwidget** ← *the `view_*` family* | — this note |
| Time nav: scroll / zoom / go-to / search | uPlot `setScale` + sweep presets (§4.2) | — |
| Annotation add / move / delete / reclassify | draw plugin keyed on `channel` (§4.4) | — |

The crucial consequence: **`get_window()` is the "server" and `view_*` is the
"client," and the contract between them already exists.** §3.5 of the blueprint
already proved the payload is uPlot-shaped — uPlot wants columnar input (one
array per series + an x array), and a `ggm_window`/`signal_table` is *already*
columnar (one column per channel). The transform is "list of columns," no
reshaping, and JSON transport is fine because the pyramid means we never ship
full resolution.

### What we borrow from lightWAVE specifically

- **Two coupled views, not one.** A detail *scope* plus a whole-record
  *navigation strip*. You never lose your place in a multi-hour study. This maps
  one-to-one onto `get_window()` (detail) + `get_overview()` (map).
- **Time is the spine of navigation.** Go-to-time, page forward/back by a screen
  width, and "find next/previous annotation" are first-class. (§3.0: time is the
  display unit; sample is the key.)
- **Server returns only what the window needs.** lightWAVE never ships a whole
  record to the browser; neither do we — the router picks a pyramid tier so the
  payload is bounded whether you ask for 4 seconds or 4 hours.
- **Annotations are a separate layer over the signal,** fetched and toggled
  independently — never baked into the trace.

### Where we deliberately diverge

- **N synced panels, not one stacked canvas.** Per §4.1 we use *N* separate uPlot
  instances linked by uPlot's `sync` API rather than one chart with 14 y-axes.
  The vertical cursor lines up across panels for free; adding/removing a channel
  is adding/removing an instance. (lightWAVE draws all signals in one SVG group;
  uPlot's canvas + sync gets us the same visual with better zoom performance.)
- **EP-native sweep speeds.** lightWAVE thinks in seconds/screen; EP reading
  happens in mm/s (25/50/100/200). The scope speaks both (§6).
- **The pyramid.** lightWAVE re-reads raw WFDB per pan; we serve a downsampled
  tier when zoomed out and only fall through to a raw `.dat` read up close
  (§4.3). This is what makes "the whole 2.7-hour ORT study on screen" cheap.

---

## 3. The `view_*` family — the R surface

Design goals: **htmlwidget-first** (every function returns something that renders
standalone in the R console, Quarto, or RMarkdown), **composable** (the full
viewer is built from the smaller pieces), and **thin** (each wraps one data-layer
call and hands columnar data to JS).

```r
# ─── the scope: the M1 keystone ────────────────────────────────────────────
view_signals(study,
             channels = NULL,        # NULL = all, else labels e.g. c("HIS D","RV 1-2")
             begin    = 0,           # seconds (§3.0 display unit)
             end      = NA,          # seconds; NA = to record end
             sweep    = 50,          # mm/s preset: 25 / 50 / 100 / 200
             px_width = 1200,        # viewport px → ppp → tier selection
             height   = NULL,        # px per panel (default auto)
             theme    = c("dark","light"))
#   → htmlwidget. N synced uPlot panels (one per channel), one shared time axis,
#     a cursor that lines up across panels. Internally: one get_window() call,
#     columns handed to uPlot as series. No editing, no live re-query.

# ─── the navigation bar: the lightWAVE strip ───────────────────────────────
view_overview(study,
              channels = NULL,
              filter   = NULL)       # e.g. type == "PaceTrain" → highlight those bands
#   → htmlwidget. Faint full-study signal tier (from the pyramid) + the sharp
#     event layer on top: shaded spans for runs/pacing trains, ticks for
#     isolated events, flags for bookmarks (§3.3b). Wraps get_overview().

# ─── the annotation layer (designed now, built at M3) ──────────────────────
view_annotations(study, range = NULL, filter = NULL)
#   → a draw layer keyed on `channel`; composes on top of a scope. Channel-
#     specific marks draw only on their panel; channel == 0 marks draw across
#     all (§4.4).

# ─── the composed viewer ───────────────────────────────────────────────────
view_study(study, channels = NULL, start = 0, sweep = 50)
#   → the lightWAVE-equivalent full viewer: overview navigation bar + scope +
#     sweep controls, linked. Standalone htmlwidget for a fixed view; the SAME
#     widgets become the Shiny module (§7) when you want live pan/zoom + edits.

# ─── convenience generic ───────────────────────────────────────────────────
view(x, ...)
#   view(study)   → view_study(study)
#   view(window)  → render an existing get_window() result directly
```

**Naming.** `view_*` is imperative and parallels the existing `get_*` accessors:
`get_window()` fetches, `view_signals()` shows. `view()` is the friendly generic;
the `view_<noun>()` forms are explicit and scriptable.

---

## 4. Data flow — concrete

One `view_signals()` call, end to end:

```
view_signals(study, c("HIS D","HIS M","RV 1-2"), begin = 12.4, end = 16.0,
             px_width = 1200)
      │
      ▼  (R, in-process — the "server")
get_window(study, channels, 12.4, 16.0, px_width = 1200)
      │   1. samples = time * fs            (§3.0)
      │   2. ppp = (end-begin)*fs / px_width
      │   3. ppp high → Parquet tier ; ppp ~1 → .dat range read
      ▼
ggm_window  (data.table)
   sample   time     HIS D    HIS M    RV 1-2
   12400    12.400   0.012   -0.004    0.220
   12401    12.401   0.015   -0.003    0.231
   …                                            attr(,"tier")="raw" ppp=… fs=1000
      │
      ▼  serialize: columnar list, NOT row objects
{ "x":      [12.400, 12.401, …],          # the shared time axis (seconds)
  "sample": [12400, 12401, …],            # carried for annotation joins (§3.0)
  "series": { "HIS D":[…], "HIS M":[…], "RV 1-2":[…] },
  "meta":   { "tier":"raw", "fs":1000, "sweep":50 } }
      │
      ▼  (browser — the "client")
uPlot × 3 instances, linked by sync key:
   panel[HIS D]  ← {x, [HIS D]}
   panel[HIS M]  ← {x, [HIS M]}
   panel[RV 1-2] ← {x, [RV 1-2]}
   shared x-scale + cursor (uPlot sync)
```

**Verified against the bundled record.** Reading `inst/extdata/bard-egm.dat`
directly (14 channels @ 1000 Hz, 3522 samples ≈ 3.52 s) confirms the columnar
shape `view_signals()` hands to uPlot — `sample` + `time` + one column per
channel, physical mV:

```
 sample  time   HIS D   HIS M  RV 1-2
   1000 1.000  0.0146  0.0130 -0.0716
   1001 1.001  0.0227  0.0009 -0.0742
   1002 1.002  0.0357 -0.0005 -0.0711
   1003 1.003  0.0562  0.0041 -0.0702
   …
```

(The §4.x walk-through above uses the blueprint's 12.4–16.0 s VOP example for
continuity; the bundled `bard-egm` record is ~3.5 s, so the M1 acceptance test
renders a window within that span.)

Two things make this cheap and are worth stating once:

1. **`x` is `time`, joins are on `sample`.** The payload carries both, which *is*
   the §3.0 boundary in practice: uPlot labels its axis in seconds; when the
   annotation layer lands it hit-tests and writes in samples.
2. **The payload is always bounded.** Zoomed in: `seconds × fs × channels` (a few
   thousand points). Zoomed out: the tier is already a few thousand LTTB points.
   Plain JSON is fine; no Arrow-over-wire needed (§3.5).

---

## 5. htmlwidget architecture (the JS side)

Standard `htmlwidgets` scaffolding, uPlot vendored locally (no CDN):

```
inst/htmlwidgets/
├── ggm_scope.js            # the binding: build N uPlot instances, sync them,
│                           #   handle resize, expose setWindow() for Shiny
├── ggm_scope.yaml          # dependencies → lib/uplot
└── lib/uplot/
    ├── uPlot.iife.min.js
    └── uPlot.min.css
```

`R/view.R` builds the payload from `get_window()` and calls
`htmlwidgets::createWidget("ggm_scope", x = payload, …)`. The binding's
`renderValue(el, payload)`:

1. For each series, create a uPlot instance in its own sub-div, all sharing one
   `sync` key so x-range/cursor/zoom move in lockstep (§4.1).
2. Set the x scale from `payload.x`; set each panel's data from its series.
3. Stash `study`/window metadata on the element so Shiny custom messages can call
   `setWindow()` to swap data on pan/zoom (§7) without rebuilding the panels —
   uPlot is stateless about series count, so "raw" ↔ "tier" swaps are just
   `setData()`.

**Why uPlot (restating the blueprint's pick):** smallest/fastest time-series
renderer; canvas handles millions of points; the `sync` API gives multi-panel
cursor alignment for free; stateless `setData()` makes the resolution handoff a
non-event.

---

## 6. Interaction model (designed now, wired at M2)

All of this funnels through one uPlot primitive — `setScale('x', {min, max})` —
exactly as §4.2 describes.

- **Sweep speed.** EP-native presets 25/50/100/200 mm/s. Visible seconds =
  `sweep_mm_s × viewport_width_mm`; a preset just sets the x-range width.
  `view_signals(sweep = 50)` is the initial value; in the live app it's a button
  group.
- **Pan / page.** Wheel or drag pans x; "page" jumps by one screen width. In the
  standalone widget this re-scales the data already shipped; in Shiny it triggers
  a fresh `get_window()` (§7).
- **Zoom + resolution handoff (§4.3).** On `hooks.setScale`, compute
  points-per-pixel, consult the manifest's `use_when_ppp_above`, pick the tier,
  `setData()`. Invisible swap. At extreme zoom-out, switch to the **two-layer
  overview** (faint signal + sharp event layer) so you navigate by *structure*,
  not by squinting at millivolts.
- **Cursor / calipers.** uPlot's synced cursor gives a vertical line aligned
  across every panel for free — the basis for measurement later.
- **Go-to-time / find annotation.** Time box + next/prev-event buttons (the
  lightWAVE "search" affordance), backed by `get_annotations()` (M3).

---

## 7. The htmlwidget ↔ Shiny seam (D-3 resolved: htmlwidget-first)

This is the most important architectural call, and it is the same seam
lightWAVE has between its client and CGI server.

**LightWAVE re-queries its server on every pan/zoom.** In `ggm` that round-trip
is: uPlot `setScale` → recompute ppp → ask R for the right tier via
`get_window()` → `setData()`. **That live re-query needs a running R process —
i.e. Shiny.** So the clean division of labor is:

- **Standalone htmlwidget** (`view_signals`, `view_overview`): renders *one
  window* (or one overview) at the tier appropriate for it. No live re-query.
  This is the perfect unit for **embedding a tracing in a Quarto/RMarkdown
  report**, for the R console, and for the **M1 "prove it renders" slice**.
- **Shiny app** (`view_study`): the *live scope*. Pan/zoom fires
  `Shiny.setInputValue`; the server calls `get_window()` for the new range/tier
  and pushes data back via a custom message → `setData()`. This is the
  "dashboard / browser" target. Annotation editing (§4.4) also lives here:
  optimistic local update + R as source of truth (a `reactiveVal` holding the
  working `annotation_table`, write-back to a derived annotator).

**Why htmlwidget-first (resolves blueprint D-3):**

1. The htmlwidget is **not throwaway** — it is the literal rendering engine the
   Shiny app drives. `view_study()`'s server does nothing but call the same
   `get_window()` and push data into the same widget. Building the widget first
   is building the engine first.
2. It is **independently useful** the day it exists: drop a tracing into a paper,
   a slide, a Quarto site — no app server required.
3. It produces a **runnable M1 slice fast** (render the bundled `bard-egm`), which
   is the blueprint's whole "vertical slices" ethos (§0).

The cost — no live pan/zoom re-query until Shiny — is exactly the boundary we
*want*, because it forces the widget and the app to share one data contract
(`get_window()`) and one JS core. Nothing is rewritten when Shiny arrives; it is
wrapped.

> **Proposed blueprint addition — D-3 `DECIDED`:** Interactive UI is
> **htmlwidget-first.** The `view_*` widgets render standalone (a fixed window);
> the Shiny `view_study()` app wraps the *same* widgets and adds live,
> server-backed pan/zoom + annotation write-back. Rationale: the widget is the
> engine the app drives, it is independently useful (Quarto/print), and it yields
> the M1 slice fastest. (Supersedes the open D-3.)

---

## 8. Annotation layer (design only; M3/M4)

Captured here so the scope is designed with it in mind, even though it is built
later (per the blueprint's milestone split).

- **Display (M3).** `view_annotations()` / a `view_signals(annotations = …)`
  option draws a marker layer over the scope. Channel attribution is **implicit
  in the panel**: a marker with `channel == "HIS D"` draws only on that panel;
  `channel == 0` (WFDB global) draws across all (§4.4). Backed by
  `get_annotations(study, range, filter)`.
- **Editing (M4).** Verbs: click-empty → add, click-near → select, drag → move
  (rewrites `sample`), delete/right-click → remove, double-click → reclassify.
  `uPlot.posToVal` converts pixel → sample; hit-test within a few px. Plus
  **snap-to-peak** (click roughly, snap to local extremum within ±N ms) — the
  ~10-line feature that makes His-potential correction bearable.
- **Write-back.** Never overwrite in place. The detector's output stays an
  immutable candidate annotator (`<record>.his`); human corrections write to a
  derived annotator (`<record>.hisr`) via `EGM::write_annotation(annotator = …)`.
  Provenance is the file extension; the corrections *are* the labeled ground
  truth for later detector tuning (§4.4).

Editing is Shiny-only by nature (it mutates R-side state), which reinforces the
§7 seam: **viewing** is widget-first; **annotating** is app-first.

---

## 9. Build order (maps to blueprint §8 milestones)

| Step | Deliverable | Depends on |
|---|---|---|
| **M1** | `view_signals()` — N synced uPlot panels rendering `bard-egm`; correct shared time scale; sweep preset as a static x-range. *No editing, no live re-query.* | M0 (done) |
| **M2** | Sweep buttons, wheel-zoom, resolution handoff (tier ↔ raw via `setScale`), `view_overview()` minimap. | M1, `build_pyramid()` |
| **M2.5** | Event pyramid + the two-layer overview inside `view_overview()`. | `get_overview()` |
| **M3** | `view_annotations()` — draw layer keyed on `channel`; filter/jump. | `get_annotations()` |
| **M4** | Editing verbs + snap-to-peak + write-back to derived annotator. | M3 + Shiny |
| **M5** | `view_study()` Shiny shell: overview + scope + chrome + mode toggle + persistent state. | M1–M4 |

**Start at M1.** Its acceptance test: open the bundled `bard-egm`
(14 channels @ 1000 Hz, ~3.5 s), call `view_signals()`, and get 14 synced panels
on one time axis that pan together — proving the `get_window()` → columnar →
uPlot path the whole interactive engine rides on.

---

## 10. Package / dependency deltas this implies

- **DESCRIPTION Imports:** add `htmlwidgets`, `htmltools`. `shiny` stays a
  *Suggests* until M5 (widgets must work without it — that is the point of §7).
- **NAMESPACE:** `export(view)`, `export(view_signals)`, `export(view_overview)`,
  `export(view_study)`, `export(view_annotations)`; S3 `print`/`knit_print` for
  the widget if needed.
- **New files:** `R/view.R` (the family + payload builder),
  `inst/htmlwidgets/ggm_scope.{js,yaml}`, `inst/htmlwidgets/lib/uplot/*`.
- **uPlot** is MIT-licensed; vendor it under `inst/htmlwidgets/lib/` with its
  license file (no CDN dependency at runtime).

---

## 11. Open questions (for §9 / §10 of the blueprint)

- **Per-panel y-scaling.** Shared µV scale across panels, per-panel autoscale, or
  per-channel-group (e.g. all CS bipoles share a gain)? EP convention usually
  fixes gain per channel; needs a `gain`/`scale` arg on `view_signals()`.
- **Channel ordering & grouping.** Honor header order, or allow a montage
  (surface leads, then His, then CS, then RV)? Likely a `montage` arg later.
- **Standalone "page" without a server.** Should the widget pre-ship a couple of
  neighbouring windows so light panning works with no Shiny? (Probably not —
  keep the seam clean; panning is the app's job.)
- **Overview interaction in a standalone widget.** Click-to-set-window needs a
  target to drive; standalone it can only emit an event. Fully realized only in
  `view_study()`.
- **Theming.** Inherit `EGM::theme_egm_*()` palettes for channel colors, or
  define a viewer theme here? (Parallels the presentation-theme question in §10.)
</content>
