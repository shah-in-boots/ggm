# A Tracing becomes SVG in a browser. tracing_spec() compiles the object to
# markup and an animation timeline; the widget at the end of this file ships
# both. Everything between is geometry and markup helpers. This is the
# presentation path -- static, print-faithful -- not a render backend in the
# gm_get_backend() sense, which is why it does not sit beside backend-uplot.R.

svgWidth <- 1000     # user units across the window
svgLane <- 120       # user units per channel lane
svgAmplitude <- 0.38 # share of a lane the trace may use, each direction


#' Compile a tracing to SVG and a timeline spec
#'
#' @param x A `Tracing`.
#' @return A list with `version`, `width`, `height`, `svg`, and `ops`.
#' @family tracing
#' @keywords internal
#' @export
tracing_spec <- function(x) {
  stopifnot(S7::S7_inherits(x, Tracing))

  height <- svgLane * length(x@channels)
  geom <- tr_geometry(x)

  parts <- c(
    tr_svg_defs(),
    tr_svg_lanes(x, geom),
    tr_svg_traces(x, geom)
  )

  ops <- list()
  arrows <- 0L
  marks <- 0L

  for (op in x@ops) {
    if (op$type == "reveal") {
      ops <- c(ops, list(list(
        type = "reveal",
        targets = ".gram-trace",
        duration = op$duration,
        stagger = op$stagger
      )))
    } else if (op$type == "arrow") {
      arrows <- arrows + 1L
      id <- paste0("gram-arrow-", arrows)
      parts <- c(parts, tr_svg_arrow(x, geom, op, id))
      ops <- c(ops, list(list(
        type = "arrow",
        targets = paste0("#", id),
        label = if (is.null(op$label)) NULL else paste0("#", id, "-label"),
        duration = op$duration
      )))
    } else if (op$type == "emphasize") {
      marks <- marks + 1L
      id <- paste0("gram-emph-", marks)
      parts <- c(parts, tr_svg_emphasis(x, geom, op, id))
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
      '<svg xmlns="http://www.w3.org/2000/svg" class="gram-tracing" ',
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
tr_geometry <- function(x) {
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

tr_geom_x <- function(geom, sample) {
  (sample - geom$sample0) / geom$width * svgWidth
}

tr_geom_baseline <- function(x, channel) {
  which(x@channels == channel)[[1L]] * svgLane - svgLane / 2
}

tr_geom_y <- function(x, geom, channel, value) {
  scale <- geom$scales[[channel]]
  tr_geom_baseline(x, channel) -
    (value - scale$centre) / scale$reach * (svgLane * svgAmplitude)
}

# value on a channel at the sample nearest the reference
tr_value_at <- function(x, ref) {
  i <- which.min(abs(x@samples - ref$sample))
  x@values[[ref$channel]][[i]]
}

# point (x, y) for a resolved reference
tr_point_at <- function(x, geom, ref) {
  c(
    tr_geom_x(geom, ref$sample),
    tr_geom_y(x, geom, ref$channel, tr_value_at(x, ref))
  )
}


# markup ----------------------------------------------------------------

tr_svg_defs <- function() {
  paste0(
    '<defs><marker id="gram-head" viewBox="0 0 10 10" refX="9" refY="5" ',
    'markerWidth="5" markerHeight="5" orient="auto-start-reverse">',
    '<path d="M 0 0 L 10 5 L 0 10 z" class="gram-head"/>',
    "</marker></defs>"
  )
}

tr_svg_lanes <- function(x, geom) {
  lanes <- vapply(x@channels, function(channel) {
    y <- tr_geom_baseline(x, channel)
    paste0(
      '<line class="gram-baseline" x1="0" y1="', gm_format_number(y),
      '" x2="', svgWidth, '" y2="', gm_format_number(y), '"/>',
      '<text class="gram-channel" x="8" y="', gm_format_number(y - svgLane * 0.32), '">',
      gm_escape_xml(channel), "</text>"
    )
  }, character(1))

  paste0('<g class="gram-lanes">', paste(lanes, collapse = ""), "</g>")
}

tr_svg_traces <- function(x, geom) {
  paths <- vapply(x@channels, function(channel) {
    xs <- tr_geom_x(geom, x@samples)
    ys <- tr_geom_y(x, geom, channel, x@values[[channel]])
    paste0(
      '<path class="gram-trace" data-channel="', gm_escape_xml(channel), '" d="',
      gm_format_path(xs, ys), '"/>'
    )
  }, character(1))

  paste0('<g class="gram-traces">', paste(paths, collapse = ""), "</g>")
}

tr_svg_arrow <- function(x, geom, op, id) {
  from <- tr_point_at(x, geom, op$from)
  to <- tr_point_at(x, geom, op$to)

  # bow the path away from the lanes it spans so it stays readable
  mx <- (from[[1L]] + to[[1L]]) / 2
  my <- (from[[2L]] + to[[2L]]) / 2
  bow <- max(svgLane * 0.35, abs(to[[2L]] - from[[2L]]) * 0.22)

  markup <- paste0(
    '<path class="gram-arrow" id="', id, '" marker-end="url(#gram-head)" ',
    'd="M ', gm_format_number(from[[1L]]), " ", gm_format_number(from[[2L]]),
    " Q ", gm_format_number(mx), " ", gm_format_number(my - bow),
    " ", gm_format_number(to[[1L]]), " ", gm_format_number(to[[2L]]), '"/>'
  )

  if (!is.null(op$label)) {
    markup <- paste0(
      markup,
      '<text class="gram-label" id="', id, '-label" ',
      'x="', gm_format_number(mx), '" y="', gm_format_number(my - bow - 8), '">',
      gm_escape_xml(op$label), "</text>"
    )
  }
  markup
}

tr_svg_emphasis <- function(x, geom, op, id) {
  pt <- tr_point_at(x, geom, op$target)
  markup <- paste0(
    '<circle class="gram-emph" id="', id, '" cx="', gm_format_number(pt[[1L]]),
    '" cy="', gm_format_number(pt[[2L]]), '" r="', gm_format_number(svgLane * 0.16), '"/>'
  )

  if (!is.null(op$label)) {
    markup <- paste0(
      markup,
      '<text class="gram-label" id="', id, '-label" ',
      'x="', gm_format_number(pt[[1L]]), '" y="', gm_format_number(pt[[2L]] - svgLane * 0.24), '">',
      gm_escape_xml(op$label), "</text>"
    )
  }
  markup
}


# helpers ---------------------------------------------------------------

# two decimals is below one screen pixel at any sane render size and
# keeps the path payload small
gm_format_number <- function(v) {
  formatC(v, format = "f", digits = 2, drop0trailing = TRUE)
}

gm_format_path <- function(xs, ys) {
  paste0("M ", paste0(gm_format_number(xs), " ", gm_format_number(ys), collapse = " L "))
}

gm_escape_xml <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  text <- gsub(">", "&gt;", text, fixed = TRUE)
  gsub('"', "&quot;", text, fixed = TRUE)
}


# widget ---------------------------------------------------------------

#' Render a tracing as an animated SVG widget
#'
#' Compiles the tracing with [tracing_spec()] and hands the markup and the
#' timeline to the browser.
#'
#' @param x A `Tracing`.
#' @param autoplay Whether the timeline runs on load.
#' @param controls Whether play, pause, and restart buttons are shown.
#' @param width,height Optional widget dimensions.
#' @param elementId Optional HTML element id.
#' @return An `htmlwidget`.
#' @family tracing
#' @keywords internal
#' @export
gram_tracing <- function(x,
                        autoplay = TRUE,
                        controls = TRUE,
                        width = NULL,
                        height = NULL,
                        elementId = NULL) {
  spec <- tracing_spec(x)

  htmlwidgets::createWidget(
    name = "gram_tracing",
    list(
      spec = spec,
      autoplay = isTRUE(autoplay),
      controls = isTRUE(controls)
    ),
    width = width,
    height = height,
    package = "gram",
    elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(
      browser.fill = TRUE,
      viewer.fill = TRUE
    )
  )
}

#' Shiny output binding for a tracing
#'
#' @param outputId Output variable to read from.
#' @param width,height Valid CSS dimensions.
#' @return A Shiny widget output element.
#' @family widgets
#' @keywords internal
#' @export
gram_tracingOutput <- function(outputId, width = "100%", height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "gram_tracing", width, height, package = "gram"
  )
}

#' Shiny render function for a tracing
#'
#' @param expr Expression that produces a [gram_tracing()] widget.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is quoted.
#' @return A Shiny render function.
#' @family widgets
#' @keywords internal
#' @export
render_gram_tracing <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(
    expr,
    gram_tracingOutput,
    env,
    quoted = TRUE
  )
}
