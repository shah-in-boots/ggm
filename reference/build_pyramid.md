# Build the signal pyramid

Compute LTTB-downsampled overview tiers for every channel and write
them, with a manifest, to a Parquet sidecar (`<record>.ggm-pyramid/`)
alongside the WFDB files. Once built,
[`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md)
binds it automatically and
[`get_window()`](https://shah-in-boots.github.io/ggm/reference/get_window.md)
serves a tier (instead of a raw read) when zoomed far out.

## Usage

``` r
build_pyramid(
  study,
  tiers = c(10, 100, 1000, 10000),
  envelope = TRUE,
  overwrite = FALSE
)
```

## Arguments

- study:

  A `ggm_study` from
  [`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md).

- tiers:

  Integer vector of downsample ratios (samples per LTTB bucket). Each
  becomes one tier; coarser tiers are tiny. Defaults to 1:10 ...
  1:10000.

- envelope:

  Whether to also store per-bucket min/max envelopes, so sharp
  deflections are never visually dropped at extreme zoom-out.

- overwrite:

  Rebuild even if a sidecar already exists.

## Value

The sidecar directory path, invisibly. Reopen the study (or call
[`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md)
again) to bind the freshly built pyramid.

## Details

The sidecar layout matches the blueprint schema:


      <record>.ggm-pyramid/
        manifest.json
        signal/channel=<id>/tier=<N>/part.parquet   # sample, value[, vmin, vmax]

Values are stored in physical units (mV). The build reads one channel at
a time to keep memory bounded on multi-hour records.

## Examples

``` r
if (FALSE) { # \dontrun{
study <- open_study("bard-egm", system.file("extdata", package = "ggm"))
build_pyramid(study, tiers = c(10, 100))
study <- open_study("bard-egm", system.file("extdata", package = "ggm")) # now bound
} # }
```
