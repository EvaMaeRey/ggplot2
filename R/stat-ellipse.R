#' Compute normal data ellipses
#'
#' The method for calculating the ellipses has been modified from
#' `car::dataEllipse` (Fox and Weisberg 2011, Friendly and Monette 2013)
#'
#' @references John Fox and Sanford Weisberg (2011). An \R Companion to
#'   Applied Regression, Second Edition. Thousand Oaks CA: Sage. URL:
#'   \url{https://uk.sagepub.com/en-gb/eur/an-r-companion-to-applied-regression/book246125}
#' @references Michael Friendly. Georges Monette. John Fox. "Elliptical Insights: Understanding Statistical Methods through Elliptical Geometry."
#' Statist. Sci. 28 (1) 1 - 39, February 2013. URL: \url{https://projecteuclid.org/journals/statistical-science/volume-28/issue-1/Elliptical-Insights-Understanding-Statistical-Methods-through-Elliptical-Geometry/10.1214/12-STS402.full}
#'
#' @param level The level at which to draw an ellipse,
#'   or, if `type="euclid"`, the radius of the circle to be drawn.
#' @param type The type of ellipse.
#'   The default `"t"` assumes a multivariate t-distribution, and
#'   `"norm"` assumes a multivariate normal distribution.
#'   `"euclid"` draws a circle with the radius equal to `level`,
#'   representing the euclidean distance from the center.
#'   This ellipse probably won't appear circular unless `coord_fixed()` is applied.
#' @param segments The number of segments to be used in drawing the ellipse.
#' @inheritParams layer
#' @inheritParams geom_point
#' @eval rd_aesthetics("stat", "ellipse")
#' @export
#' @examples
#' ggplot(faithful, aes(waiting, eruptions)) +
#'   geom_point() +
#'   stat_ellipse()
#'
#' ggplot(faithful, aes(waiting, eruptions, color = eruptions > 3)) +
#'   geom_point() +
#'   stat_ellipse()
#'
#' ggplot(faithful, aes(waiting, eruptions, color = eruptions > 3)) +
#'   geom_point() +
#'   stat_ellipse(type = "norm", linetype = 2) +
#'   stat_ellipse(type = "t")
#'
#' ggplot(faithful, aes(waiting, eruptions, color = eruptions > 3)) +
#'   geom_point() +
#'   stat_ellipse(type = "norm", linetype = 2) +
#'   stat_ellipse(type = "euclid", level = 3) +
#'   coord_fixed()
#'
#' ggplot(faithful, aes(waiting, eruptions, fill = eruptions > 3)) +
#'   stat_ellipse(geom = "polygon")
stat_ellipse <- function(mapping = NULL, data = NULL,
                         geom = "path", position = "identity",
                         ...,
                         type = "t",
                         level = 0.95,
                         segments = 51,
                         na.rm = FALSE,
                         show.legend = NA,
                         inherit.aes = TRUE) {
  layer(
    data = data,
    mapping = mapping,
    stat = StatEllipse,
    geom = geom,
    position = position,
    show.legend = show.legend,
    inherit.aes = inherit.aes,
    params = list2(
      type = type,
      level = level,
      segments = segments,
      na.rm = na.rm,
      ...
    )
  )
}

#' @rdname ggplot2-ggproto
#' @format NULL
#' @usage NULL
#' @export
StatEllipse <- ggproto("StatEllipse", Stat,
  required_aes = c("x", "y"),
  optional_aes = "weight",
  dropped_aes = "weight",

  setup_params = function(data, params) {
    params$type <- params$type %||% "t"
    if (identical(params$type, "t")) {
      check_installed("MASS", "for calculating ellipses with `type = \"t\"`.")
    }
    params
  },

  compute_group = function(data, scales, type = "t", level = 0.95,
                           segments = 51, na.rm = FALSE) {
    calculate_ellipse(data = data, vars = c("x", "y"), type = type,
                      level = level, segments = segments)
  }
)

calculate_ellipse <- function(data, vars, type, level, segments){
  dfn <- 2
  dfd <- nrow(data) - 1

  weight <- data$weight %||% rep(1, nrow(data))
  weight <- weight / sum(weight)

  if (!type %in% c("t", "norm", "euclid")) {
    cli::cli_inform("Unrecognized ellipse type")
    ellipse <- matrix(NA_real_, ncol = 2)
  } else if (dfd < 3) {
    cli::cli_inform("Too few points to calculate an ellipse")
    ellipse <- matrix(NA_real_, ncol = 2)
  } else {
    if (type == "t") {
      # Prone to convergence problems when `sum(weight) != nrow(data)`
      v <- MASS::cov.trob(data[,vars], wt = weight * nrow(data))
    } else if (type == "norm") {
      v <- stats::cov.wt(data[,vars], wt = weight)
    } else if (type == "euclid") {
      v <- stats::cov.wt(data[,vars], wt = weight)
      v$cov <- diag(rep(min(diag(v$cov)), 2))
    }
    shape <- v$cov
    center <- v$center
    chol_decomp <- chol(shape)
    if (type == "euclid") {
      radius <- level/max(chol_decomp)
    } else {
      radius <- sqrt(dfn * stats::qf(level, dfn, dfd))
    }
    angles <- (0:segments) * 2 * pi/segments
    unit.circle <- cbind(cos(angles), sin(angles))
    ellipse <- t(center + radius * t(unit.circle %*% chol_decomp))
  }

  colnames(ellipse) <- vars
  mat_2_df(ellipse)
}
