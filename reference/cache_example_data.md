# Download an example study to the local cache

Fetch a `ggm` example WFDB record to a local directory, downloading it
once and reusing the cached copy thereafter. A WFDB record is a pair of
files that together form one dataset — a `.hea` text header and a `.dat`
binary signal — and both are fetched. The returned directory drops
straight into
[`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md).

## Usage

``` r
cache_example_data(
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

  Re-download even if the files are already present (useful if a cached
  copy is suspected truncated).

- quiet:

  Passed to
  [`utils::download.file()`](https://rdrr.io/r/utils/download.file.html);
  `FALSE` (default) shows a progress bar, reassuring for a
  multi-hundred-MB transfer.

## Value

The path to `dir` (invisibly when a download happened, so a fresh pull
does not dump a path mid-pipeline). The record's `.hea`/`.dat` are
guaranteed present on return, so
`open_study(dataset, cache_example_data(dataset))` always works.

## Details

Each file downloads to a `.part` sidecar and is renamed into place only
on success, so an interrupted transfer never leaves a truncated file
that later looks "cached". The download timeout is raised for the call
(the 60 s default is far too short for these files) and restored on
exit.

## See also

[`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md)
to open the downloaded record.

## Examples

``` r
if (FALSE) { # \dontrun{
# Download (once) and open the large ORT study:
study <- open_study("ort", cache_example_data("ort"))
study
} # }
```
