# Largest-Triangle-Three-Buckets downsampling (blueprint S3.2).
#
# LTTB preserves the *shape* of a trace (peaks, sharp deflections) at a small
# fraction of the points, which is exactly what electrograms need — the
# morphology is the information. This is the per-tier reducer the signal pyramid
# is built from.
#
# Pure R for now. It is a one-time, cached build step, so correctness matters
# more than speed here; a cpp11 port is the planned optimisation (blueprint S7)
# if building the finest tiers on multi-hour records proves too slow.

# Downsample one channel to roughly `threshold` points via LTTB, optionally
# attaching the per-bucket min/max envelope so a sharp spike is never visually
# dropped at extreme zoom-out.
#
# Returns a data.table with columns sample, value (+ vmin, vmax if envelope).
lttb_reduce <- function(sample, value, threshold, envelope = TRUE) {
  n <- length(value)
  threshold <- as.integer(threshold)

  # Degenerate: nothing to reduce (threshold meaningless or >= the data). Keep
  # every point; the envelope of a single-point "bucket" is the point itself.
  if (threshold <= 2L || threshold >= n) {
    out <- data.table::data.table(sample = sample, value = value)
    if (envelope) {
      out$vmin <- value
      out$vmax <- value
    }
    return(out)
  }

  idx <- integer(threshold)
  vmin <- rep(NA_real_, threshold)
  vmax <- rep(NA_real_, threshold)

  # First point is always kept.
  idx[1L] <- 1L
  vmin[1L] <- value[1L]
  vmax[1L] <- value[1L]

  bucket_size <- (n - 2) / (threshold - 2)
  a <- 0L # 0-based index of the previously selected point

  for (i in 0:(threshold - 3L)) {
    # Average point of the *next* bucket, used as the far vertex of the triangle.
    avg_start <- floor((i + 1) * bucket_size) + 1
    avg_end <- min(floor((i + 2) * bucket_size) + 1, n)
    ja <- (avg_start + 1L):avg_end
    if (avg_start + 1L > avg_end) ja <- n # tail guard
    avg_x <- mean(sample[ja])
    avg_y <- mean(value[ja])

    # Points of the *current* bucket; pick the one forming the largest triangle.
    rng_start <- floor(i * bucket_size) + 1
    rng_end <- floor((i + 1) * bucket_size) + 1
    jb <- (rng_start + 1L):rng_end
    ax <- sample[a + 1L]
    ay <- value[a + 1L]
    area <- abs((ax - avg_x) * (value[jb] - ay) - (ax - sample[jb]) * (avg_y - ay))
    sel <- jb[which.max(area)]

    idx[i + 2L] <- sel
    if (envelope) {
      vmin[i + 2L] <- min(value[jb])
      vmax[i + 2L] <- max(value[jb])
    }
    a <- sel - 1L
  }

  # Last point is always kept.
  idx[threshold] <- n
  vmin[threshold] <- value[n]
  vmax[threshold] <- value[n]

  out <- data.table::data.table(sample = sample[idx], value = value[idx])
  if (envelope) {
    out$vmin <- vmin
    out$vmax <- vmax
  }
  out
}
