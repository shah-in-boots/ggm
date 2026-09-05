# Parked from {EGM} 0.2.x, where it was `R/ggm.R`. EGM dropped its plotting
# layer in 0.3.0 so that {ggplot2} could leave its Imports; the code lives here
# until it is wired to gram's own window reads. Nothing in this file is exported
# or reached by the rest of the package yet, and the integration point is
# undecided: `gram_plot()` takes a per-channel panel payload, and this takes a
# whole `EGM` object, so one of the two has to move.
#
# Kept as close to the original as it can be while loading in this package.
# Three things had to change:
#
#   * gram has no NAMESPACE imports, so every ggplot2 call is qualified.
#   * gram does not import data.table, and `[.data.table` with `:=` from a
#     namespace that is not data.table-aware falls back to data.frame
#     semantics and silently does nothing. The reshape to long form is base R.
#   * EGM's canonical channel order (`.labels`) is internal to EGM. The header
#     already levels `label` by it when every label is a known one, so the
#     order is read off the header rather than looked up.


# plot ------------------------------------------------------------------

#' Visualise an EGM with ggplot2
#'
#' Plots an object of the `EGM` class, one lane per channel, coloured as the
#' recording system coloured them. More than a plotting function, it is a way
#' to confirm patterns, annotations and underlying waveforms in the data: the
#' header and annotations ride along on the returned object so that
#' annotations, intervals and measurements can be layered on incrementally.
#'
#' @param data An `EGM` object, holding header (meta) and signal information
#'   together.
#' @param channels A `character` vector of channels to draw. Either a channel
#'   label (`"CS 1-2"`) or the recording device or catheter (`"His"`, `"ECG"`),
#'   matched as a pattern. All channels when empty.
#' @param time_frame A `numeric` of length 2, start and end in seconds. The
#'   whole record when `NULL`.
#' @param ... Unused.
#' @return A `ggplot` with the additional class `ggm`, carrying the header and
#'   annotations of the original data as attributes.
#' @keywords internal
#' @noRd
ggm <- function(data, channels = character(), time_frame = NULL, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("ggm() needs the ggplot2 package", call. = FALSE)
  }
  stopifnot(inherits(data, "EGM"))

  # Clean channels
  channels <- gsub("_", " ", x = channels)

  # Process header and signal
  hea <- data$header
  # Get first annotation from list (or empty if none)
  ann_list <- data$annotation
  if (length(ann_list) > 0) {
    ann <- ann_list[[1]]
    if (length(ann_list) > 1) {
      message(
        "Multiple annotators found: ",
        paste(names(ann_list), collapse = ", "),
        ". Using '", names(ann_list)[1], "' for plotting. ",
        "Use EGM::get_annotation() to access other annotators."
      )
    }
  } else {
    ann <- EGM::annotation_table()
  }
  sig <- as.data.frame(data$signal)
  labelOrder <- if (is.factor(hea$label)) levels(hea$label) else NULL
  hea$label <- gsub("_", " ", x = as.character(hea$label))
  names(sig) <- c("sample", hea$label)

  # Should be all of the same frequency of data
  hz <- attributes(hea)$record_line$frequency
  sig$time <- sig$sample / hz

  # check if time frame exists within series, allowing for
  # indexed rounding based on frequency
  if (is.null(time_frame)) {
    time_frame <- c(min(sig$time, na.rm = TRUE), max(sig$time, na.rm = TRUE))
  }
  stopifnot(
    "`time_frame` must be within available data" = all(
      min(time_frame) + 1 / hz >= min(sig$time) &
        max(time_frame) - 1 / hz <= max(sig$time)
    )
  )

  # Filter time appropriately based on samples.
  # ponytail: exact float equality on `time`, so a frame not landing on a
  # sample selects nothing; round to the nearest sample when this is wired in.
  sampleStart <- sig$sample[sig$time == time_frame[1]]
  sampleEnd <- sig$sample[sig$time == time_frame[2]]

  # Trim the signal and annotation files to match the time frame
  sig <- sig[sig$sample >= sampleStart & sig$sample <= sampleEnd, ]
  ann <- ann[ann$sample >= sampleStart & ann$sample <= sampleEnd, ]

  # Make sure appropriate channels are selected
  availableChannels <- hea$label
  known <- if (is.null(labelOrder)) availableChannels else labelOrder
  exactChannels <- channels[channels %in% known]
  fuzzyChannels <- channels[!(channels %in% known)]
  channelGrep <- paste0(
    c(paste0("^", exactChannels, "$", collapse = "|"), fuzzyChannels),
    collapse = "|"
  )
  selectedChannels <- grep(channelGrep, availableChannels, value = TRUE)
  if (length(channels) == 0) {
    selectedChannels <- availableChannels
  }
  stopifnot(
    "The requested channels do not exist within the signal data" =
      length(selectedChannels) > 0
  )

  # Long form: one row per sample per selected channel, with the header's
  # colour joined on by label
  channelData <- data.frame(
    label = hea$label,
    source = as.character(hea$source),
    lead = as.character(hea$lead),
    color = as.character(hea$color),
    stringsAsFactors = FALSE
  )
  dt <- do.call(rbind, lapply(selectedChannels, function(channel) {
    data.frame(
      sample = sig$sample,
      time = sig$time,
      label = channel,
      mV = as.numeric(sig[[channel]]),
      stringsAsFactors = FALSE
    )
  }))
  dt <- merge(dt, channelData, by = "label", all.x = TRUE, sort = FALSE)
  dt <- dt[order(dt$label, dt$sample), ]

  # Relevel because order is lost in the labels during transformation
  # But only do this if the labels are... "official" and not custom labels
  if (!is.null(labelOrder) && all(selectedChannels %in% labelOrder)) {
    dt$label <- factor(
      dt$label,
      levels = intersect(labelOrder, selectedChannels),
      ordered = TRUE
    )
  } else {
    dt$label <- factor(dt$label, levels = selectedChannels)
  }

  # Create final plot
  g <-
    ggplot2::ggplot(
      dt,
      ggplot2::aes(x = sample, y = mV, colour = color)
    ) +
    ggplot2::geom_line() +
    ggplot2::facet_wrap(
      ~label,
      ncol = 1,
      scales = "free_y",
      strip.position = "left"
    ) +
    ggplot2::scale_colour_identity() +
    ggplot2::scale_x_continuous(
      breaks = seq(sampleStart, sampleEnd, by = hz),
      labels = NULL
    )

  # Respect default header colours while ensuring a contrasting background
  selectedColors <- unique(stats::na.omit(dt$color))
  toRgb <- function(colour) {
    tryCatch(
      as.numeric(grDevices::col2rgb(colour)),
      error = function(...) rep(NA_real_, 3)
    )
  }
  isWhite <- function(colourVector) {
    !any(is.na(colourVector)) && all(colourVector >= 250)
  }
  isBlack <- function(colourVector) {
    !any(is.na(colourVector)) && all(colourVector <= 5)
  }
  colourVectors <- lapply(selectedColors, toRgb)
  hasWhite <- any(vapply(colourVectors, isWhite, logical(1)))
  hasBlack <- any(vapply(colourVectors, isBlack, logical(1)))

  backgroundMode <- "default"
  if (hasWhite && !hasBlack) {
    backgroundMode <- "dark"
  } else if (hasBlack) {
    backgroundMode <- "light"
  }

  # Update class, then apply the theme for the chosen background
  g <- new_ggm(g, header = hea, annotation = ann)
  g + theme_egm(background = backgroundMode)
}

new_ggm <- function(object = ggplot2::ggplot(),
                    header = list(),
                    annotation = EGM::annotation_table()) {
  stopifnot(ggplot2::is_ggplot(object))

  structure(
    object,
    header = header,
    annotation = annotation,
    class = c("ggm", class(object))
  )
}


# theme -----------------------------------------------------------------

#' Theme and colour options for `ggm` objects
#'
#' Improves visibility of electrical signals. Recording software tends to
#' colour channels in a consistent pattern, and these themes let that pattern
#' through against a background that contrasts with it.
#'
#' @param background The canvas: `"default"` for the standard appearance,
#'   `"dark"` for a black canvas suited to light traces, or `"light"` for a
#'   white canvas suited to dark traces.
#' @return A `ggplot2` theme, or a list of theme and scale for the `_light`
#'   and `_dark` variants, to add to a `ggm` object.
#' @keywords internal
#' @noRd
theme_egm <- function(background = c("default", "dark", "light")) {
  background <- match.arg(background)
  # mark/theme-colors.R has theme_brand(), but mark/ is .Rbuildignored and
  # cannot be called from here
  baseTheme <-
    ggplot2::`%+replace%`(
      ggplot2::theme_minimal(),
      ggplot2::theme(
        # Panels
        panel.grid.major.y = ggplot2::element_blank(),
        panel.grid.minor.y = ggplot2::element_blank(),
        panel.grid.major.x = ggplot2::element_blank(),
        panel.grid.minor.x = ggplot2::element_blank(),

        # Axes
        axis.ticks.y = ggplot2::element_blank(),
        axis.title.y = ggplot2::element_blank(),
        axis.text.y = ggplot2::element_blank(),
        axis.title.x = ggplot2::element_blank(),
        axis.ticks.x = ggplot2::element_line(),

        # Facets
        panel.spacing = ggplot2::unit(0, units = "npc"),
        panel.background = ggplot2::element_blank(),
        strip.text.y.left = ggplot2::element_text(angle = 0, hjust = 1),

        # Legend
        legend.position = "none"
      )
    )

  if (background == "dark") {
    baseTheme <-
      baseTheme +
      ggplot2::theme(
        panel.background = ggplot2::element_rect(fill = "black", colour = NA),
        plot.background = ggplot2::element_rect(fill = "black", colour = NA),
        strip.text.y.left = ggplot2::element_text(color = "white"),
        axis.text.x = ggplot2::element_text(color = "white"),
        axis.ticks.x = ggplot2::element_line(color = "white")
      )
  } else if (background == "light") {
    baseTheme <-
      baseTheme +
      ggplot2::theme(
        panel.background = ggplot2::element_rect(fill = "white", colour = NA),
        plot.background = ggplot2::element_rect(fill = "white", colour = NA),
        strip.text.y.left = ggplot2::element_text(color = "black"),
        axis.text.x = ggplot2::element_text(color = "black"),
        axis.ticks.x = ggplot2::element_line(color = "black")
      )
  }

  baseTheme
}

#' @rdname theme_egm
#' @noRd
theme_egm_light <- function() {
  list(
    theme_egm(background = "light"),
    # Force every trace to black on the white canvas
    ggplot2::scale_color_manual(
      values = rep("black", 64),
      na.value = "black"
    )
  )
}

#' @rdname theme_egm
#' @noRd
theme_egm_dark <- function() {
  list(
    theme_egm(background = "dark"),
    # Force every trace to white on the black canvas
    ggplot2::scale_color_manual(
      values = rep("white", 64),
      na.value = "white"
    )
  )
}
