# Download an example study to the local cache

Fetch a `ggm` example WFDB record to a local directory, downloading it
once and reusing the cached copy thereafter. A WFDB record is a pair of
files that together form one dataset — a `.hea` text header and a `.dat`
binary signal — and both are fetched.

## Usage

``` r
cache_study_data(
  dataset = "ort",
  dir = tools::R_user_dir("ggm", "cache"),
  force = FALSE,
  quiet = FALSE
)
```

## Arguments

- dataset:

  Example record name. Currently only `"ort"` (the default): a
  27-channel intracardiac study, 977 Hz, ~2.7 hours (~516 MB).

- dir:

  Directory to cache into. Defaults to the package's per-user cache
  (`tools::R_user_dir("ggm", "cache")`), the CRAN-sanctioned location
  for downloaded data. Pass e.g. `"data-raw"` to download elsewhere.

- force:

  Re-download even if the files are already cached (useful if a cached
  copy is suspected truncated or stale).

- quiet:

  Suppress piggyback's download progress bar.

## Value

The path to `dir` (invisibly when a download happened, so a fresh pull
does not dump a path mid-pipeline). The record's `.hea`/`.dat` are
guaranteed present on return, so
`open_study(dataset, cache_example_data(dataset))` always works.

## Details

Downloads use the piggyback package (the same tool that publishes the
assets). Install it with `install.packages("piggyback")` if prompted.

If the record's files are already present in `dir`, this returns
immediately without contacting GitHub. Otherwise it delegates to
[`piggyback::pb_download()`](https://docs.ropensci.org/piggyback/reference/pb_download.html),
which fetches only the missing files (or, with `force`, re-fetches them
regardless of timestamps).
