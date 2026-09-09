#' Build the sealed environment a tracing script runs in
#'
#' The returned environment holds the tracing verbs and nothing else. Its
#' parent is `emptyenv()`, so a name the grammar does not define cannot be
#' reached from a script.
#'
#' @param cache A `StudyCache`, bound as the source for [tracing()].
#' @return An environment.
#' @family grammar
#' @keywords internal
#' @export
gram_verbs <- function(cache) {
  env <- new.env(parent = emptyenv())

  # the study is bound here, so a script never names it
  env$tracing <- function(...) tracing(cache = cache, ...)

  env$at <- at
  env$reveal <- reveal
  env$add_arrow <- add_arrow
  env$emphasize <- emphasize

  env$c <- c
  env$`:` <- `:`

  env
}

#' Evaluate a tracing script
#'
#' Parses `text`, rejects anything outside the grammar, and evaluates the
#' result in the sealed environment from [gram_verbs()].
#'
#' @param text A single string holding the script.
#' @param cache A `StudyCache`.
#' @return The `Tracing` the script produced.
#' @family grammar
#' @keywords internal
#' @export
eval_tracing <- function(text, cache) {
  if (length(text) != 1L || !is.character(text)) {
    stop("`text` must be a single string", call. = FALSE)
  }

  exprs <- tryCatch(
    parse(text = text),
    error = function(e) {
      stop("could not parse the script: ", conditionMessage(e), call. = FALSE)
    }
  )
  if (length(exprs) == 0L) {
    stop("the script is empty", call. = FALSE)
  }

  env <- gram_verbs(cache)
  allowed <- ls(env, all.names = TRUE)
  for (expr in exprs) {
    gm_check_grammar(expr, allowed)
  }

  result <- NULL
  for (expr in exprs) {
    result <- eval(expr, envir = env)
  }

  if (!S7::S7_inherits(result, Tracing)) {
    stop(
      "the script must end in a tracing; it produced ",
      paste(class(result), collapse = "/"),
      call. = FALSE
    )
  }
  result
}

# Walk one expression, rejecting anything the grammar does not define.
# Runs before evaluation, so a rejected script never executes.
gm_check_grammar <- function(expr, allowed) {
  if (is.call(expr)) {
    fn <- expr[[1L]]
    if (!is.symbol(fn)) {
      if (is.call(fn) && as.character(fn[[1L]]) %in% c("::", ":::")) {
        stop(
          "the grammar has no packages to reach into; call a verb by name",
          call. = FALSE
        )
      }
      stop(
        "only a named verb may be called; found a computed call",
        call. = FALSE
      )
    }
    name <- as.character(fn)
    if (!name %in% allowed) {
      stop(
        "`", name, "` is not part of the tracing grammar (available: ",
        paste(sort(allowed), collapse = ", "), ")",
        call. = FALSE
      )
    }
    for (arg in as.list(expr)[-1L]) {
      gm_check_grammar(arg, allowed)
    }
  } else if (is.symbol(expr)) {
    name <- as.character(expr)
    if (nzchar(name) && !name %in% allowed) {
      stop("`", name, "` is not defined in the tracing grammar", call. = FALSE)
    }
  } else if (!is.null(expr) && !is.atomic(expr)) {
    stop("unsupported expression in the script", call. = FALSE)
  }
  invisible(TRUE)
}
