# tracing-svg.R -------------------------------------------------------
# Compiles a Tracing into SVG markup plus an ordered timeline spec.
#
# One coordinate space: channels are lanes stacked by vertical offset, so
# an arrow between any two points is a single path with two endpoints
# whatever lanes they sit in.
#
# The spec names selectors, durations, and order. It never names an
# anime.js option; ggm-anim.js owns those.

svgWidth <- 1000     # user units across the window
svgLane <- 120       # user units per channel lane
svgAmplitude <- 0.38 # share of a lane the trace may use, each direction


#' Compile a tracing to SVG and a timeline spec
#'
#' @param x A `Tracing`.
#' @return A list with `version`, `width`, `height`, `svg`, and `ops`.
#' @family tracing
#' @export
tracing_spec <- function(x) {
  stopifnot(S7::S7_inherits(x, Tracing))

  height <- svgLane * length(x@channels)
  geom <- tracing_geometry(x)

  parts <- c(
    svg_defs(),
    svg_lanes(x, geom),
    svg_traces(x, geom)
  )

  ops <- list()
  arrows <- 0L
  marks <- 0L

  for (op in x@ops) {
    if (op$type == "reveal") {
      ops <- c(ops, list(list(
        type = "reveal",
        targets = ".ggm-trace",
        duration = op$duration,
        stagger = op$stagger
      )))
    } else if (op$type == "arrow") {
      arrows <- arrows + 1L
      id <- paste0("ggm-arrow-", arrows)
      parts <- c(parts, svg_arrow(x, geom, op, id))
      ops <- c(ops, list(list(
        type = "arrow",
        targets = paste0("#", id),
        label = if (is.null(op$label)) NULL else paste0("#", id, "-label"),
        duration = op$duration
      )))
    } else if (op$type == "emphasize") {
      marks <- marks + 1L
      id <- paste0("ggm-emph-", marks)
      parts <- c(parts, svg_emphasis(x, geom, op, id))
      ops <- c(ops, list(list(
        type = "emphasize",
        targets = paste0("#", id),
        label = if (is.null(op$label)) NULL else paste0("#", id, "-label"),
        duration = op$duration
      )))
    }
  }

  list(
    version = tracingSpecVersion,
    width = svgWidth,
    height = height,
    svg = paste0(
      '<svg xmlns="http://www.w3.org/2000/svg" class="ggm-tracing" ',
      'viewBox="0 0 ', svgWidth, ' ', height, '" ',
      'preserveAspectRatio="xMidYMid meet">',
      paste(parts, collapse = ""),
      "</svg>"
    ),
    ops = ops
  )
}


# geometry --------------------------------------------------------------

# per-channel scaling and the sample -> x mapping, computed once
tracing_geometry <- function(x) {
  span <- range(x@samples)
  width <- span[[2L]] - span[[1L]]
  if (width <= 0) width <- 1

  scales <- lapply(x@channels, function(channel) {
    v <- x@values[[channel]]
    centre <- stats::median(v, na.rm = TRUE)
    reach <- max(abs(v - centre), na.rm = TRUE)
    if (!is.finite(reach) || reach == 0) reach <- 1
    list(centre = centre, reach = reach)
  })
  names(scales) <- x@channels

  list(sample0 = span[[1L]], width = width, scales = scales)
}

geom_x <- function(geom, sample) {
  (sample - geom$sample0) / geom$width * svgWidth
}

geom_baseline <- function(x, channel) {
  which(x@channels == channel)[[1L]] * svgLane - svgLane / 2
}

geom_y <- function(x, geom, channel, value) {
  scale <- geom$scales[[channel]]
  geom_baseline(x, channel) -
    (value - scale$centre) / scale$reach * (svgLane * svgAmplitude)
}

# value on a channel at the sample nearest the reference
value_at <- function(x, ref) {
  i <- which.min(abs(x@samples - ref$sample))
  x@values[[ref$channel]][[i]]
}

# point (x, y) for a resolved reference
point_at <- function(x, geom, ref) {
  c(
    geom_x(geom, ref$sample),
    geom_y(x, geom, ref$channel, value_at(x, ref))
  )
}


# markup ----------------------------------------------------------------

svg_defs <- function() {
  paste0(
    '<defs><marker id="ggm-head" viewBox="0 0 10 10" refX="9" refY="5" ',
    'markerWidth="5" markerHeight="5" orient="auto-start-reverse">',
    '<path d="M 0 0 L 10 5 L 0 10 z" class="ggm-head"/>',
    "</marker></defs>"
  )
}

svg_lanes <- function(x, geom) {
  lanes <- vapply(x@channels, function(channel) {
    y <- geom_baseline(x, channel)
    paste0(
      '<line class="ggm-baseline" x1="0" y1="', num(y),
      '" x2="', svgWidth, '" y2="', num(y), '"/>',
      '<text class="ggm-channel" x="8" y="', num(y - svgLane * 0.32), '">',
      escape_xml(channel), "</text>"
    )
  }, character(1))

  paste0('<g class="ggm-lanes">', paste(lanes, collapse = ""), "</g>")
}

svg_traces <- function(x, geom) {
  paths <- vapply(x@channels, function(channel) {
    xs <- geom_x(geom, x@samples)
    ys <- geom_y(x, geom, channel, x@values[[channel]])
    paste0(
      '<path class="ggm-trace" data-channel="', escape_xml(channel), '" d="',
      path_data(xs, ys), '"/>'
    )
  }, character(1))

  paste0('<g class="ggm-traces">', paste(paths, collapse = ""), "</g>")
}

svg_arrow <- function(x, geom, op, id) {
  from <- point_at(x, geom, op$from)
  to <- point_at(x, geom, op$to)

  # bow the path away from the lanes it spans so it stays readable
  mx <- (from[[1L]] + to[[1L]]) / 2
  my <- (from[[2L]] + to[[2L]]) / 2
  bow <- max(svgLane * 0.35, abs(to[[2L]] - from[[2L]]) * 0.22)

  markup <- paste0(
    '<path class="ggm-arrow" id="', id, '" marker-end="url(#ggm-head)" ',
    'd="M ', num(from[[1L]]), " ", num(from[[2L]]),
    " Q ", num(mx), " ", num(my - bow),
    " ", num(to[[1L]]), " ", num(to[[2L]]), '"/>'
  )

  if (!is.null(op$label)) {
    markup <- paste0(
      markup,
      '<text class="ggm-label" id="', id, '-label" ',
      'x="', num(mx), '" y="', num(my - bow - 8), '">',
      escape_xml(op$label), "</text>"
    )
  }
  markup
}

svg_emphasis <- function(x, geom, op, id) {
  pt <- point_at(x, geom, op$target)
  markup <- paste0(
    '<circle class="ggm-emph" id="', id, '" cx="', num(pt[[1L]]),
    '" cy="', num(pt[[2L]]), '" r="', num(svgLane * 0.16), '"/>'
  )

  if (!is.null(op$label)) {
    markup <- paste0(
      markup,
      '<text class="ggm-label" id="', id, '-label" ',
      'x="', num(pt[[1L]]), '" y="', num(pt[[2L]] - svgLane * 0.24), '">',
      escape_xml(op$label), "</text>"
    )
  }
  markup
}


# helpers ---------------------------------------------------------------

# two decimals is below one screen pixel at any sane render size and
# keeps the path payload small
num <- function(v) {
  formatC(v, format = "f", digits = 2, drop0trailing = TRUE)
}

path_data <- function(xs, ys) {
  paste0("M ", paste0(num(xs), " ", num(ys), collapse = " L "))
}

escape_xml <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  text <- gsub(">", "&gt;", text, fixed = TRUE)
  gsub('"', "&quot;", text, fixed = TRUE)
}
