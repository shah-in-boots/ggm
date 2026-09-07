# All paths in a study group

All paths in a study group

## Usage

``` r
cache_paths(cache)
```

## Arguments

- cache:

  A `StudyCache`.

## Value

Named character vector of record paths: `data`, `header`, `manifest`,
one `annotation_<ext>` per sidecar, and `cache` when an overview has
been built.

## See also

Other cache:
[`cache_annotators()`](https://shah-in-boots.github.io/gram/reference/cache_annotators.md),
[`cache_study_data()`](https://shah-in-boots.github.io/gram/reference/cache_study_data.md),
[`study_cache()`](https://shah-in-boots.github.io/gram/reference/study_cache.md)
