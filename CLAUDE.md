# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`ggm` (Grammar of Electrograms) is an R package: the visualization and interaction
layer for cardiac electrophysiology signal data. It is the L2–L4 stack on top of
the **EGM** package (`Depends: EGM`, pulled from `shah-in-boots/EGM` via `Remotes`),
which owns canonical WFDB signal I/O. `ggm` never re-implements what EGM does —
it calls `EGM::read_header()` / `EGM::read_signal()` for byte-seek reads and adds
windowed access, a multi-resolution overview, and (planned) a declarative grammar
for figures.

The package is early/experimental. Only the **data backend** (milestone M0) is
partly built; most of the read API and all of the UI/grammar layers are deliberate
stubs. **`blueprint.md` is the design source of truth** — it carries the layer map,
milestone roadmap (M0–M8), and a decision log (D-1…D-9). Read the relevant section
before extending an area; source files reference it (e.g. "blueprint S3.4").

## Commands

R package tooling (devtools/testthat). Run from the package root:

```r
devtools::load_all()        # load package for interactive work
devtools::document()        # regenerate man/*.Rd and NAMESPACE from roxygen2
devtools::test()            # run all tests
devtools::check()           # full R CMD check (what CI runs)

testthat::test_file("tests/testthat/test-window.R")   # one test file
```

There is no separate lint step. Code style is enforced by **Air** (the Posit R
formatter, `air.toml`), applied on save in VS Code (`Posit.air-vscode`). A GitHub
Action (`format-suggest.yaml`) suggests Air formatting on PRs. Don't restyle code
unrelated to your change.

CI (`R-CMD-check.yaml`) runs `R CMD check` across macOS/Windows/Linux and several
R versions (devel → oldrel-4); the minimum is R >= 4.1.0.

## The one rule that governs the data layer (D-8)

**Sample index (integer) is the canonical key for storage, computation, and joins.
Time (seconds) is the presentation unit.** Conversion is exact and free:
`time = sample / frequency`, `sample = round(time * frequency)`.

In practice: user-facing arguments speak **seconds**, internal work happens in
**samples**, and returned data carries **both** columns (`sample` for the
renderer's annotation joins, `time` for its axis). The conversion lives in exactly
one place — `time_to_sample()` / `sample_to_time()` in `R/convert.R`. Use them;
never open-code the arithmetic.

## Architecture

The read path is a small set of S3 objects and one router. Read these together to
get the big picture:

- **`R/study.R` — `open_study(record, record_dir)`** is the entry point everything
  sits on. It is deliberately *lazy*: on open it reads only the small WFDB header
  (via EGM) and records where the signal lives, so opening a multi-hour study is
  instant and memory stays bounded. Returns a `ggm_study` (an S3 list with
  `record`, `frequency`, `n_samples`, `channels`, `duration`, and a bound
  `pyramid` if a sidecar exists). Signal samples are pulled per-window, never on
  open.

- **`R/window.R` — `get_window(study, channels, begin, end, px_width, units)`** is
  the single surface renderers read through. Time window in seconds → work in
  samples → returns a `ggm_window` (an EGM `signal_table`/`data.table` with
  `sample`, `time`, and one column per channel, plus `tier`/`ppp`/`frequency`
  attributes). It routes between **two stores, two jobs**:
  - **raw path** (`read_window_raw`) — a direct `.dat` byte-seek range read via
    `EGM::read_signal()`. Great at "these channels, this window, full detail."
  - **tier path** (`read_window_tier`) — reads LTTB-reduced points from the Parquet
    pyramid for far-zoomed-out views. Channels were reduced independently, so they
    land on different sample indices and get unioned onto a shared grid via
    `dcast` (NA where a channel has no point — the columnar "gap" form renderers
    expect).
  - `.select_tier()` is the decision: keyed on **points-per-pixel** (`ppp`,
    computed from `px_width`). Currently always returns `"raw"` unless a pyramid is
    bound and zoom is coarse enough; digital-unit requests always stay raw (the
    pyramid stores physical units only).

- **`R/pyramid.R` — `build_pyramid(study, tiers, envelope, overwrite)`** precomputes
  the downsampled overview the `.dat` cannot give cheaply. It reads each channel at
  full resolution once, LTTB-reduces it at several zoom tiers, and writes a
  **regenerable Parquet sidecar** next to the record:
  ```
  <record>.ggm-pyramid/
    manifest.json
    signal/channel=<id>/tier=<N>/part.parquet   # sample, value[, vmin, vmax]
  ```
  The pyramid stores *only derived* data (physical units, mV) — never raw `.dat`
  samples. `open_study()` binds an existing sidecar automatically via
  `bind_pyramid()`; the router reads the manifest to choose tiers.

- **`R/lttb.R` — `lttb_reduce()`** is the per-tier reducer: Largest-Triangle-
  Three-Buckets downsampling, which preserves trace *shape* (peaks, sharp
  deflections) — the morphology is the clinical information. Pure R for now; a
  cpp11 port is the planned optimization (blueprint S7) if needed. Optionally
  stores per-bucket min/max envelopes so spikes are never visually dropped.

- **`R/access.R` — `get_overview()`, `get_annotations()`** round out the read API
  but are **stubs** (planned M2.5 / M3). They fail loudly via
  `not_yet_implemented()` rather than silently no-op'ing.

- **`R/example-data.R` — `cache_example_data()`** downloads the large `ort` demo
  record (~516 MB WFDB pair) from a GitHub Release into the per-user cache via
  `piggyback` (a *Suggests*, checked at call time). The "already cached?" check
  runs before any network call.

Layering (from `blueprint.md` S2), built bottom-up: **L0** canonical WFDB storage
(EGM) → **L1** derived/regenerable index+cache (signal & event pyramids) → **L2**
this R data-access API → **L3** grammar/Shiny app → **L4** renderers (uPlot live,
SVG+GSAP presentation). Only L0–L2 partly exist today.

## Conventions

- **S3, not S4/R6.** Objects are classed lists (`ggm_study`, `ggm_window`) with
  `print` methods. `is_study()` is the type guard; validate it at the top of
  functions that take a study.
- **Naming:** data accessors are `get_*`; constructors are nouns (`study`,
  eventually `scene`); grammar verbs will be imperative (`measure`, `emphasize`).
- **roxygen2 with Markdown** (`Roxygen: list(markdown = TRUE)`). `NAMESPACE` and
  `man/*.Rd` are **generated** — edit the roxygen comments above the function and
  run `devtools::document()`, never hand-edit those files.
- **data.table by reference.** The package is `.datatable.aware`; cheap column work
  uses `data.table::set()` / `setcolorder()` rather than copying frames.
- **Stubs name their milestone.** Unbuilt API surface calls
  `not_yet_implemented("fn()", "M3")` (in `R/ggm-package.R`), which raises a
  `ggm_not_implemented` condition. Tests assert on that class and the milestone
  string — keep stubs callable and loud.
- **Errors are strict and at the boundary** (`call. = FALSE`, with the available
  options listed). See `resolve_channels()` and `check_frequency()` for the house
  style.

## Tests

testthat 3rd edition (`tests/testthat/`), one `test-*.R` per `R/*.R`. Shared
fixtures live in `tests/testthat/helper-ggm.R`:

- The bundled sample record is **`bard-egm`** (`inst/extdata/bard-egm.*`): 14
  channels, 1000 Hz, 3522 samples (~3.5 s). Open it with `open_test_study()`.
- `local_bard_dir()` copies the record into a temp dir so pyramid sidecars can be
  built and torn down without touching `inst/extdata`.
- The large `ort` record routes through `cache_example_data()` so tests exercise
  the same download path users do; missing data / offline becomes a clean `skip()`,
  not a failure (see `ort_record_dir()`).

Tests double as the **behavioral contract** — e.g. `test-window.R` pins the exact
output column order (`sample`, `time`, then channels in requested order), sample
ranges, and the `tier`/`ppp` attributes. If you change a returned shape, update
the asserted contract deliberately.

## Contributing notes (from .github/CONTRIBUTING.md)

Follows the tidyverse model: tidyverse style guide (apply with Air), roxygen2 +
Markdown for docs, testthat for tests. PRs should pass `devtools::check()` cleanly
and add a `NEWS.md` bullet for user-facing changes.
