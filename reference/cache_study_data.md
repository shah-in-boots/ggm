# Download an example study to the local cache

Fetch a `gram` example WFDB record — the `.hea` header and the `.dat`
signal — to a local directory, downloading it once and reusing the
cached copy thereafter. Downloads use the piggyback package.

## Usage

``` r
cache_study_data(
  dataset = "ort",
  dir = tools::R_user_dir("gram", "cache"),
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
  (`tools::R_user_dir("gram", "cache")`).

- force:

  Re-download even if the files are already cached.

- quiet:

  Suppress piggyback's download progress bar.

## Value

The path to `dir`, invisibly when a download happened.

## See also

Other cache:
[`cache_annotators()`](https://shah-in-boots.github.io/gram/reference/cache_annotators.md),
[`cache_paths()`](https://shah-in-boots.github.io/gram/reference/cache_paths.md),
[`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md)
