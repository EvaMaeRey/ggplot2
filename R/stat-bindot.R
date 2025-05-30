#' @rdname ggplot2-ggproto
#' @format NULL
#' @usage NULL
#' @export
StatBindot <- ggproto("StatBindot", Stat,
  required_aes = "x",
  non_missing_aes = "weight",
  default_aes = aes(y = after_stat(count)),
  dropped_aes = c("bin", "bincenter"), # these are temporary variables that are created and then removed by the stat

  setup_params = function(data, params) {
    if (is.null(params$binwidth)) {
      cli::cli_inform("Bin width defaults to 1/30 of the range of the data. Pick better value with {.arg binwidth}.")
    }
    params
  },

  compute_layer = function(self, data, params, layout) {
    data <- remove_missing(data, params$na.rm, name = snake_class(self))
    ggproto_parent(Stat, self)$compute_layer(data, params, layout)
  },

  compute_panel = function(self, data, scales, na.rm = FALSE, binwidth = NULL,
                           binaxis = "x", method = "dotdensity",
                           binpositions = "bygroup", origin = NULL,
                           width = 0.9, drop = FALSE,
                           right = TRUE) {

    # If using dotdensity and binning over all, we need to find the bin centers
    # for all data before it's split into groups.
    if (method == "dotdensity" && binpositions == "all") {
      if (binaxis == "x") {
        newdata <- densitybin(x = data$x, weight = data$weight, binwidth = binwidth,
                      method = method)

        data    <- data[order(data$x), ]
        newdata <- newdata[order(newdata$x), ]

      } else if (binaxis == "y") {
        newdata <- densitybin(x = data$y, weight = data$weight, binwidth = binwidth,
                    method = method)

        data    <- data[order(data$y), ]
        newdata <- newdata[order(newdata$x), ]
      }

      data$bin       <- newdata$bin
      data$binwidth  <- newdata$binwidth
      data$weight    <- newdata$weight
      data$bincenter <- newdata$bincenter

    }

    ggproto_parent(Stat, self)$compute_panel(data, scales, binwidth = binwidth,
      binaxis = binaxis, method = method, binpositions = binpositions,
      origin = origin, width = width, drop = drop,
      right = right)
  },

  compute_group = function(self, data, scales, binwidth = NULL, binaxis = "x",
                           method = "dotdensity", binpositions = "bygroup",
                           origin = NULL, width = 0.9, drop = FALSE,
                           right = TRUE) {
    # Check that weights are whole numbers (for dots, weights must be whole)
    if (!is.null(data$weight) && !(is_integerish(data$weight) && all(data$weight >= 0))) {
      stop_input_type(data$weight, "nonnegative integers", arg = "weight")
    }

    if (binaxis == "x") {
      range   <- scales$x$dimension()
      values  <- data$x
    } else if (binaxis == "y") {
      range  <- scales$y$dimension()
      values <- data$y
      # The middle of each group, on the stack axis
      midline <- mean(range(data$x))
    }

    if (method == "histodot") {
      bins <- compute_bins(
        values, scales[[binaxis]],
        breaks = NULL, binwidth = binwidth, bins = 30, center = NULL,
        boundary = origin, closed = if (right) "right" else "left"
      )
      data <- bin_vector(values, bins, weight = data$weight, pad = FALSE)

      # Change "width" column to "binwidth" for consistency
      names(data)[names(data) == "width"] <- "binwidth"
      names(data)[names(data) == "x"]     <- "bincenter"

    } else if (method == "dotdensity") {

      # If bin centers are found by group instead of by all, find the bin centers
      # (If binpositions=="all", then we'll already have bin centers.)
      if (binpositions == "bygroup")
        data <- densitybin(x = values, weight = data$weight, binwidth = binwidth,
                  method = method, range = range)

      # Collapse each bin and get a count
      data <- dapply(data, "bincenter", function(x) {
        data_frame0(
          binwidth = .subset2(x, "binwidth")[1],
          count = sum(.subset2(x, "weight")),
          .size = 1
        )
      })

      if (sum(data$count, na.rm = TRUE) != 0) {
        data$count[is.na(data$count)] <- 0
        data$ncount <- data$count / max(abs(data$count), na.rm = TRUE)
        if (drop) data <- subset(data, count > 0)
      }
    }

    if (binaxis == "x") {
      names(data)[names(data) == "bincenter"] <- "x"
      # For x binning, the width of the geoms is same as the width of the bin
      data$width <- data$binwidth
    } else if (binaxis == "y") {
      names(data)[names(data) == "bincenter"] <- "y"
      # For y binning, set the x midline. This is needed for continuous x axis
      data$x <- midline
    }
    return(data)
  },

  dropped_aes = c("weight", "bin", "bincenter")
)


# This does density binning, but does not collapse each bin with a count.
# It returns a data frame with the original data (x), weights, bin #, and the bin centers.
densitybin <- function(x, weight = NULL, binwidth = NULL, method = method, range = NULL) {

    if (length(stats::na.omit(x)) == 0) return(data_frame0())
    if (is.null(weight))  weight <- rep(1, length(x))
    weight[is.na(weight)] <- 0

    if (is.null(range))    range <- range(x, na.rm = TRUE, finite = TRUE)
    if (is.null(binwidth)) binwidth <- diff(range) / 30

    # Sort weight and x, by x
    weight <- weight[order(x)]
    x      <- sort(x, na.last = TRUE)

    cbin    <- 0                      # Current bin ID
    bin     <- rep.int(NA, length(x)) # The bin ID for each observation
    binend  <- -Inf                   # End position of current bin (scan left to right)

    # Scan list and put dots in bins
    for (i in seq_along(x)) {
        # If past end of bin, start a new bin at this point
        if (x[i] >= binend) {
            binend <- x[i] + binwidth
            cbin <- cbin + 1
        }

        bin[i] <- cbin
    }

    results <- data_frame0(
      x = x,
      bin = bin,
      binwidth = binwidth,
      weight = weight,
      .size = length(x)
    )
    results <- dapply(results, "bin", function(df) {
      df$bincenter = (min(df$x) + max(df$x)) / 2
      return(df)
    })

    return(results)
}
