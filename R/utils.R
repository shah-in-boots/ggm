#' Tiny if/or operator
#' Used to avoid calling rlang 
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x
