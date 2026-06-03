# ggm: A Grammar for Exploring and Presenting Cardiac Electrograms

`ggm` (Grammar of Electrograms) is the visualization and interaction
layer for cardiac electrophysiology signal data. It builds on the EGM
data backend (WFDB-compatible I/O, `signal_table`/`header_table`) and
never re-implements what `EGM` already does well.

## The sample/time boundary (D-8)

One rule governs the whole data layer: the integer **sample index** is
the canonical key for storage, computation, and joins, while **time
(seconds)** is the presentation unit. The conversion is exact and free
(`time = sample / frequency`). User-facing arguments speak seconds;
internal work happens in samples; results carry both. See
[`time_to_sample()`](https://shah-in-boots.github.io/ggm/reference/convert.md)
and
[`sample_to_time()`](https://shah-in-boots.github.io/ggm/reference/convert.md).

## Where to start

- [`open_study()`](https://shah-in-boots.github.io/ggm/reference/open_study.md)
  binds a record + header into a `ggm_study`.

- [`get_window()`](https://shah-in-boots.github.io/ggm/reference/get_window.md)
  is the windowed-read router that feeds renderers.

## See also

Useful links:

- <https://shah-in-boots.github.io/ggm/>

## Author

**Maintainer**: Anish S. Shah <shah.in.boots@gmail.com>
([ORCID](https://orcid.org/0000-0002-9729-1558)) \[copyright holder\]

Authors:

- Anish S. Shah <shah.in.boots@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-9729-1558)) \[copyright holder\]
