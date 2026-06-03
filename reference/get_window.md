# Read a window of signal

The adaptive windowed read that feeds the renderers. Give it a time
window (seconds) and the channels you want; it returns those channels
over that window with both `sample` and `time` columns.

## Usage

``` r
get_window(
  study,
  channels = NULL,
  begin = 0,
  end = NA,
  px_width = NULL,
  units = c("physical", "digital")
)
```

## Arguments

- study:

  A `ggm_study` from
  [`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md).

- channels:

  Character vector of channel labels to read. `NULL` (default) reads
  every channel in the study.

- begin, end:

  Window bounds in **seconds**. `end = NA` (default) reads to the end of
  the record.

- px_width:

  Width of the target viewport in pixels. Optional; when given, it is
  used to compute points-per-pixel and (in a future milestone) choose a
  downsampled tier. It does not change the data in this spine release.

- units:

  `"physical"` (mV, default — what you plot) or `"digital"` (raw ADC
  integers). Passed through to
  [`EGM::read_signal()`](https://shah-in-boots.github.io/EGM/reference/wfdb_io.html).

## Value

A `ggm_window`: an `EGM` `signal_table` (a `data.table`) with a `sample`
column, a `time` column (seconds), and one column per requested channel.
Carries attributes `tier` (which source served it — `"raw"` for a direct
`.dat` read), `ppp` (points-per-pixel, or `NA`), and `frequency`.

## Examples

``` r
if (FALSE) { # \dontrun{
study <- open_study("bard-egm", system.file("extdata", package = "ggm"))
w <- get_window(study, channels = c("HIS D", "RV 1-2"), begin = 1, end = 2)
attr(w, "tier")
} # }
```
