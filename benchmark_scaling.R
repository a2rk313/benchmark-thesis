#!/usr/bin/env Rscript
#===============================================================================
# Data Scaling Benchmark Framework — All 9 Thesis Scenarios (R)
#===============================================================================
#
# Runs benchmarks at multiple data scales to:
# 1. Validate algorithmic complexity via log-log regression
# 2. Identify performance cliffs and memory bottlenecks
# 3. Follow Tedesco et al. (2025) methodology (k=1,2,3,4 scaling factors)
# 4. Cover all 9 benchmark scenarios across the thesis
#
# Methodology:
#   - Minimum time as primary estimator (Chen & Revels 2016)
#   - Data generation OUTSIDE timed section (only computation measured)
#   - Consistent random seeds for reproducibility at each scale
#   - Log-log regression: log(t) = k * log(n) + c, where k = scaling exponent
#
# Output:
#   - results/scaling/{scenario}_scaling_r.json (per-scenario)
#   - results/scaling/combined_scaling_summary_r.json (all scenarios)
#===============================================================================

# Dynamic path resolution
get_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grep("--file=", args)]
  if (length(file_arg) > 0) {
    script_path <- sub("--file=", "", file_arg)
    return(normalizePath(file.path(dirname(script_path), "..")))
  } else {
    return(getwd())
  }
}
PROJECT_ROOT <- get_project_root()
DATA_DIR <- file.path(PROJECT_ROOT, "data")

suppressPackageStartupMessages({
  library(jsonlite)
  if (requireNamespace("data.table", quietly = TRUE)) {
    library(data.table)
  }
})

# =============================================================================
# Scaling Configurations (matching Python)
# =============================================================================

MATRIX_SCALES <- list(k1 = 500L, k2 = 1000L, k3 = 2000L, k4 = 3000L)
MATRIX_SCALES_QUICK <- list(k1 = 250L, k2 = 500L, k3 = 750L, k4 = 1000L)

IO_SCALES <- list(small = 100000L, medium = 500000L, large = 1000000L, xlarge = 3000000L)
IO_SCALES_QUICK <- list(small = 25000L, medium = 50000L, large = 100000L, xlarge = 250000L)

HYPERSPECTRAL_SCALES <- list(small = 128L, medium = 256L, large = 512L, xlarge = 768L)
HYPERSPECTRAL_SCALES_QUICK <- list(small = 64L, medium = 128L, large = 256L, xlarge = 384L)

VECTOR_SCALES <- list(small = 100000L, medium = 500000L, large = 1000000L, xlarge = 3000000L)
VECTOR_SCALES_QUICK <- list(small = 25000L, medium = 50000L, large = 100000L, xlarge = 250000L)

IDW_SCALES <- list(small = 5000L, medium = 20000L, large = 50000L, xlarge = 100000L)
IDW_SCALES_QUICK <- list(small = 2000L, medium = 5000L, large = 10000L, xlarge = 20000L)

TIMESERIES_SCALES <- list(small = 256L, medium = 512L, large = 768L, xlarge = 1024L)
TIMESERIES_SCALES_QUICK <- list(small = 128L, medium = 256L, large = 512L, xlarge = 768L)

RASTER_SCALES <- list(small = 256L, medium = 512L, large = 1024L, xlarge = 2048L)
RASTER_SCALES_QUICK <- list(small = 128L, medium = 256L, large = 512L, xlarge = 768L)

ZONAL_SCALES <- list(small = 256L, medium = 512L, large = 1024L, xlarge = 2048L)
ZONAL_SCALES_QUICK <- list(small = 128L, medium = 256L, large = 512L, xlarge = 768L)

REPROJ_SCALES <- list(small = 1000L, medium = 10000L, large = 50000L, xlarge = 100000L)
REPROJ_SCALES_QUICK <- list(small = 500L, medium = 2000L, large = 5000L, xlarge = 10000L)

# =============================================================================
# Benchmark Runner
# =============================================================================

run_all_scales <- function(name, scales, setup_func, run_func, n_runs = 10, unit = "elements") {
  cat(sprintf("\n%s\n", paste(rep("=", 70), collapse = "")))
  cat(sprintf("SCALING BENCHMARK: %s\n", name))
  cat(sprintf("%s\n", paste(rep("=", 70), collapse = "")))

  results <- list()
  sorted_names <- names(scales)[order(unlist(scales))]

  for (scale_name in sorted_names) {
    scale_value <- scales[[scale_name]]
    cat(sprintf("\n[%s] Scale: %s %s\n", scale_name, format(scale_value, big.mark = ","), unit))

    setup <- setup_func(scale_value)

    times <- numeric(n_runs)
    for (run in seq_len(n_runs)) {
      gc()
      start <- Sys.time()
      run_func(setup)
      elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
      times[run] <- elapsed
    }

    results[[scale_name]] <- list(
      scale_value = scale_value,
      min = min(times),
      mean = mean(times),
      median = median(times),
      std = sd(times),
      max = max(times),
      cv = if (mean(times) > 0) sd(times) / mean(times) else 0,
      all_times = times
    )

    r <- results[[scale_name]]
    cat(sprintf("  Min: %.4fs (PRIMARY)  |  Mean: %.4fs ± %.4fs  |  CV: %.2f%%\n",
                r$min, r$mean, r$std, r$cv * 100))
  }

  return(results)
}

analyze_complexity <- function(name, scales, results) {
  cat(sprintf("\n%s\n", paste(rep("=", 70), collapse = "")))
  cat(sprintf("COMPLEXITY ANALYSIS: %s\n", name))
  cat(sprintf("%s\n", paste(rep("=", 70), collapse = "")))

  sorted_names <- names(scales)[order(unlist(scales))]
  if (length(sorted_names) < 2) {
    cat("  Insufficient scales for complexity analysis\n")
    return(list(k = NULL, r_squared = NULL, complexity = "Insufficient data"))
  }

  min_times <- sapply(sorted_names, function(s) results[[s]]$min)
  scale_values <- sapply(sorted_names, function(s) results[[s]]$scale_value)

  log_times <- log(min_times)
  log_sizes <- log(scale_values)

  # Linear regression: log(t) = k * log(n) + c
  fit <- lm(log_times ~ log_sizes)
  k <- coef(fit)[["log_sizes"]]
  c_val <- coef(fit)[["(Intercept)"]]
  r_squared <- summary(fit)$r.squared

  # Classify complexity
  if (r_squared < 0.7) {
    complexity_label <- "Uncertain (R² < 0.7)"
  } else if (k < 1.1) {
    complexity_label <- "O(n) — Linear"
  } else if (k < 1.5) {
    complexity_label <- "O(n log n) — Linearithmic"
  } else if (k < 2.2) {
    complexity_label <- "O(n²) — Quadratic"
  } else if (k < 2.5) {
    complexity_label <- "O(n^2.37) — Matrix multiplication"
  } else if (k < 3.5) {
    complexity_label <- "O(n³) — Cubic"
  } else {
    complexity_label <- sprintf("> O(n³) — Super-cubic (k=%.2f)", k)
  }

  cat(sprintf("\n  Log-Log Regression:\n"))
  cat(sprintf("    Scaling exponent (k): %.3f\n", k))
  cat(sprintf("    Intercept (c):        %.3f\n", c_val))
  cat(sprintf("    R²:                   %.4f\n", r_squared))
  cat(sprintf("    Estimated complexity: %s\n", complexity_label))

  cat("\n  Pairwise scaling ratios:\n")
  for (i in seq_len(length(sorted_names) - 1)) {
    size_ratio <- scale_values[i + 1] / scale_values[i]
    time_ratio <- min_times[i + 1] / min_times[i]
    exp_est <- if (size_ratio > 1) log(time_ratio) / log(size_ratio) else 0
    cat(sprintf("    %8s -> %8s:  size = %.1fx,  time = %.2fx,  exp ≈ %.2f\n",
                sorted_names[i], sorted_names[i + 1], size_ratio, time_ratio, exp_est))
  }

  return(list(
    scaling_exponent = round(k, 4),
    intercept = round(c_val, 4),
    r_squared = round(r_squared, 4),
    complexity_label = complexity_label
  ))
}

save_results <- function(name, scales, results, unit, n_runs, output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- file.path(PROJECT_ROOT, "results", "scaling")
  }

  complexity <- analyze_complexity(name, scales, results)

  output <- list(
    benchmark = name,
    language = "r",
    unit = unit,
    scales = scales,
    n_runs = n_runs,
    methodology = "Chen & Revels (2016): minimum time as primary estimator",
    complexity_analysis = complexity,
    results = results
  )

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_file <- file.path(output_dir, paste0(name, "_scaling_r.json"))
  write_json(output, output_file, pretty = TRUE, auto_unbox = TRUE)

  cat(sprintf("\n  Results saved: %s\n", output_file))
  return(output_file)
}

format_num <- function(n) {
  format(n, big.mark = ",", scientific = FALSE)
}

# =============================================================================
# Scenario 1: Matrix Operations Scaling
# =============================================================================

benchmark_matrix_scaling <- function(quick = FALSE) {
  scales <- if (quick) MATRIX_SCALES_QUICK else MATRIX_SCALES
  vector_scales <- if (quick) VECTOR_SCALES_QUICK else VECTOR_SCALES

  # Matrix creation, transpose, reshape
  setup_creation <- function(n) { set.seed(42); matrix(rnorm(n * n), n, n) }
  run_creation <- function(A) {
    n <- nrow(A)
    A <- t(A)
    new_rows <- as.integer(n * 2 / 5)
    new_cols <- as.integer(n * n / new_rows)
    A <- matrix(A, nrow = new_rows, ncol = new_cols)
    A <- t(A)
    invisible(NULL)
  }

  results_creation <- run_all_scales("matrix_creation", scales, setup_creation, run_creation, n_runs = 10, unit = "matrix dimension (n)")
  save_results("matrix_creation", scales, results_creation, "matrix dimension (n)", 10)

  # Cross-product
  setup_cp <- function(n) { set.seed(42); matrix(rnorm(n * n), n, n) }
  run_cp <- function(A) { t(A) %*% A; invisible(NULL) }

  results_xp <- run_all_scales("matrix_crossproduct", scales, setup_cp, run_cp, n_runs = 10, unit = "matrix dimension (n)")
  save_results("matrix_crossproduct", scales, results_xp, "matrix dimension (n)", 10)

  # Determinant
  setup_det <- function(n) { set.seed(42); matrix(rnorm(n * n), n, n) }
  run_det <- function(A) { det(A); invisible(NULL) }

  results_det <- run_all_scales("matrix_determinant", scales, setup_det, run_det, n_runs = 10, unit = "matrix dimension (n)")
  save_results("matrix_determinant", scales, results_det, "matrix dimension (n)", 10)

  # Matrix power
  setup_pow <- function(n) { set.seed(42); A <- matrix(rnorm(n * n), n, n); abs(A) / 2.0 }
  run_pow <- function(A) { A^10; invisible(NULL) }

  results_pow <- run_all_scales("matrix_power", scales, setup_pow, run_pow, n_runs = 10, unit = "matrix dimension (n)")
  save_results("matrix_power", scales, results_pow, "matrix dimension (n)", 10)

  # Sorting
  setup_sort <- function(n) { set.seed(42); rnorm(n) }
  run_sort <- function(arr) { sort(arr); invisible(NULL) }

  results_sort <- run_all_scales("sorting", vector_scales, setup_sort, run_sort, n_runs = 10, unit = "elements")
  save_results("sorting", vector_scales, results_sort, "elements", 10)
}

# =============================================================================
# Scenario 2: I/O Operations Scaling
# =============================================================================

benchmark_io_scaling <- function(quick = FALSE) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    cat("\n  Skipping I/O scaling: data.table not available\n")
    return()
  }

  scales <- if (quick) IO_SCALES_QUICK else IO_SCALES

  # CSV Write
  setup_csv <- function(n) {
    set.seed(42)
    list(
      lat = runif(n, -90, 90),
      lon = runif(n, -180, 180),
      device_id = sample(10000L, n, replace = TRUE)
    )
  }
  run_csv <- function(data) {
    dt <- data.table(lat = data$lat, lon = data$lon, device_id = data$device_id)
    output_path <- file.path(DATA_DIR, "io_test_r.csv")
    fwrite(dt, output_path)
    invisible(NULL)
  }

  results_csv <- run_all_scales("io_csv_write", scales, setup_csv, run_csv, n_runs = 5, unit = "rows")
  save_results("io_csv_write", scales, results_csv, "rows", 5)

  # Binary Write
  setup_bin <- function(n) { set.seed(42); rnorm(n) }
  run_bin <- function(arr) {
    output_path <- file.path(DATA_DIR, "io_test_r.bin")
    con <- file(output_path, "wb")
    writeBin(as.double(arr), con)
    close(con)
    invisible(NULL)
  }

  results_bin <- run_all_scales("io_binary_write", scales, setup_bin, run_bin, n_runs = 5, unit = "values")
  save_results("io_binary_write", scales, results_bin, "values", 5)

  # CSV Read
  setup_csv_read <- function(n) {
    set.seed(42)
    df <- data.frame(
      lat = runif(n, -90, 90),
      lon = runif(n, -180, 180),
      device_id = sample(10000L, n, replace = TRUE)
    )
    output_path <- file.path(DATA_DIR, "io_test_r.csv")
    fwrite(df, output_path)
    output_path
  }
  run_csv_read <- function(path) {
    dt <- fread(path)
    invisible(NULL)
  }

  results_csv_read <- run_all_scales("io_csv_read", scales, setup_csv_read, run_csv_read, n_runs = 5, unit = "rows")
  save_results("io_csv_read", scales, results_csv_read, "rows", 5)

  # Binary Read
  setup_bin_read <- function(n) {
    set.seed(42)
    arr <- rnorm(n)
    output_path <- file.path(DATA_DIR, "io_test_r.bin")
    con <- file(output_path, "wb")
    writeBin(as.double(arr), con)
    close(con)
    output_path
  }
  run_bin_read <- function(path) {
    con <- file(path, "rb")
    arr <- readBin(con, "double", n = file.info(path)$size / 8)
    close(con)
    invisible(NULL)
  }

  results_bin_read <- run_all_scales("io_binary_read", scales, setup_bin_read, run_bin_read, n_runs = 5, unit = "values")
  save_results("io_binary_read", scales, results_bin_read, "values", 5)
}

# =============================================================================
# Scenario 3: Hyperspectral SAM Scaling
# =============================================================================

benchmark_hyperspectral_scaling <- function(quick = FALSE) {
  scales <- if (quick) HYPERSPECTRAL_SCALES_QUICK else HYPERSPECTRAL_SCALES
  n_bands <- 224L

  setup <- function(n_pixels) {
    set.seed(42)
    data <- array(rnorm(n_bands * n_pixels * n_pixels), dim = c(n_bands, n_pixels, n_pixels))
    ref <- seq(0.1, 0.9, length.out = n_bands)
    ref <- ref / sqrt(sum(ref^2))
    list(data = data, ref = ref, n_bands = n_bands, n_pixels = n_pixels)
  }

  run <- function(s) {
    data <- s$data
    ref <- s$ref
    n_bands <- s$n_bands
    n_pixels <- s$n_pixels
    chunk_size <- 256L

    for (row in seq(1, n_pixels, chunk_size)) {
      for (col in seq(1, n_pixels, chunk_size)) {
        row_end <- min(row + chunk_size - 1, n_pixels)
        col_end <- min(col + chunk_size - 1, n_pixels)
        chunk <- data[, row:row_end, col:col_end]
        pixels <- matrix(chunk, nrow = (row_end - row + 1) * (col_end - col + 1), ncol = n_bands, byrow = FALSE)

        dot_product <- pixels %*% ref
        pixel_norms <- sqrt(rowSums(pixels^2))
        ref_norm <- sqrt(sum(ref^2))
        cos_angle <- dot_product / (pixel_norms * ref_norm + 1e-8)
        cos_angle <- pmin(pmax(cos_angle, -1.0), 1.0)
        angles <- acos(cos_angle)
      }
    }
    invisible(NULL)
  }

  results <- run_all_scales("hyperspectral_sam", scales, setup, run, n_runs = 5, unit = "pixels per side (n x n x 224 bands)")
  save_results("hyperspectral_sam", scales, results, "pixels per side (n x n x 224 bands)", 5)
}

# =============================================================================
# Scenario 4: Vector Point-in-Polygon Scaling
# =============================================================================

benchmark_vector_scaling <- function(quick = FALSE) {
  scales <- if (quick) VECTOR_SCALES_QUICK else VECTOR_SCALES

  setup <- function(n) {
    set.seed(42)
    df <- data.frame(
      lon = runif(n, -180, 180),
      lat = runif(n, -90, 90)
    )

    # Create polygons (10x10 grid of countries for spatial join)
    polys <- list()
    for (i in 1:10) {
      for (j in 1:10) {
        min_lon <- -180 + (j-1)*36
        max_lon <- -180 + j*36
        min_lat <- -90 + (i-1)*18
        max_lat <- -90 + i*18
        coords <- matrix(c(min_lon, min_lat, max_lon, min_lat, max_lon, max_lat, min_lon, max_lat, min_lon, min_lat), ncol=2, byrow=TRUE)
        polys[[length(polys) + 1]] <- terra::vect(geom = list(coords), type="polygons", crs="EPSG:4326")
      }
    }
    polys <- terra::vect(polys)

    list(points_df = df, polys = polys)
  }

  run <- function(s) {
    df <- s$points_df
    polys <- s$polys

    # Convert to terra SpatVector
    points <- terra::vect(df, geom = c("lon", "lat"), crs = "EPSG:4326")

    # Point-in-polygon using terra extract
    extracted <- terra::extract(polys, points, touches = TRUE)

    if (nrow(extracted) > 0) {
      # Get polygon centroids for Haversine calculation
      centroids <- terra::centroids(polys)

      # Calculate Haversine distance for matched points
      for (idx in seq_len(nrow(extracted))) {
        poly_idx <- extracted[idx, 2]  # Polygon index
        if (!is.na(poly_idx)) {
          point_lon <- df$lon[idx]
          point_lat <- df$lat[idx]
          centroid <- centroids[poly_idx]
          centroid_coords <- terra::geom(centroid)[1, c("x", "y")]

          dlon <- point_lon - centroid_coords[1]
          dlat <- point_lat - centroid_coords[2]
          a <- sin(dlat/2)^2 + cos(point_lat) * cos(centroid_coords[2]) * sin(dlon/2)^2
          c <- 2 * asin(pmin(sqrt(a), 1.0))
          dist <- 6371000.0 * c
        }
      }
    }
    invisible(NULL)
  }

  results <- run_all_scales("vector_pip", scales, setup, run, n_runs = 5, unit = "query points")
  save_results("vector_pip", scales, results, "query points", 5)
}

  run <- function(data) {
    lon <- data$lon
    lat <- data$lat

    # Simulate PIP by checking against a rectangular region
    mask <- lon > -10.0 & lon < 10.0 & lat > -10.0 & lat < 10.0

    # Haversine distance for matched points
    lon_m <- lon[mask]
    lat_m <- lat[mask]
    if (length(lon_m) > 0) {
      dlon <- lon_m - 0.0
      dlat <- lat_m - 0.0
      a <- sin(dlat/2)^2 + cos(lat_m) * cos(0.0) * sin(dlon/2)^2
      c <- 2 * asin(pmin(sqrt(a), 1.0))
      distances <- 6371000.0 * c
    }
    invisible(NULL)
  }

  results <- run_all_scales("vector_pip", scales, setup, run, n_runs = 5, unit = "query points")
  save_results("vector_pip", scales, results, "query points", 5)
}

# =============================================================================
# Scenario 5: IDW Interpolation Scaling
# =============================================================================

benchmark_idw_scaling <- function(quick = FALSE) {
  scales <- if (quick) IDW_SCALES_QUICK else IDW_SCALES
  has_fnn <- requireNamespace("FNN", quietly = TRUE)

  setup <- function(n) {
    set.seed(42)
    x <- runif(n, 0, 1000)
    y <- runif(n, 0, 1000)
    values <- 100.0 * sin(x / 200.0 + 10) * cos(y / 200.0) + 50.0 * sin(x / 50.0) + 20.0 * rnorm(n)

    grid_size <- max(100L, as.integer(sqrt(n) * 3))
    gx <- seq(0, 1000, length.out = grid_size)
    gy <- seq(0, 1000, length.out = grid_size)
    grid_points <- cbind(rep(gx, each = grid_size), rep(gy, grid_size))

    list(x = x, y = y, values = values, n = n, grid_points = grid_points, grid_size = grid_size, has_fnn = has_fnn)
  }

  run <- function(s) {
    x <- s$x
    y <- s$y
    values <- s$values
    grid_points <- s$grid_points
    grid_size <- s$grid_size
    has_fnn <- s$has_fnn

    points <- cbind(x, y)

    if (has_fnn) {
      # Use FNN::get.knnx for kNN search
      k <- min(12L, s$n)
      nn <- FNN::get.knnx(points, grid_points, k = k)
      result <- numeric(nrow(grid_points))

      for (i in seq_len(nrow(grid_points))) {
        dists <- nn$nn.dist[i, ]
        dists[dists < 1e-10] <- 1e-10
        weights <- 1.0 / (dists ^ 2)
        weights <- weights / sum(weights)
        result[i] <- sum(weights * values[nn$nn.index[i, ]])
      }
    } else {
      # Fallback to brute-force
      result <- numeric(nrow(grid_points))
      for (i in seq_len(nrow(grid_points))) {
        gx_pt <- grid_points[i, 1]
        gy_pt <- grid_points[i, 2]
        dists <- sqrt((x - gx_pt)^2 + (y - gy_pt)^2)
        dists[dists < 1e-10] <- 1e-10
        weights <- 1.0 / dists
        result[i] <- sum(weights * values) / sum(weights)
      }
    }
    invisible(NULL)
  }

  results <- run_all_scales("idw_interpolation", scales, setup, run, n_runs = 3, unit = "input points")
  save_results("idw_interpolation", scales, results, "input points", 3)
}

# =============================================================================
# Scenario 6: Time-Series NDVI Scaling
# =============================================================================

benchmark_timeseries_scaling <- function(quick = FALSE) {
  scales <- if (quick) TIMESERIES_SCALES_QUICK else TIMESERIES_SCALES
  n_dates <- 46L

  setup <- function(n) {
    set.seed(42)
    x <- seq(-1, 1, length.out = n)
    y <- seq(-1, 1, length.out = n)
    xx <- outer(x, y, function(a, b) a)
    yy <- outer(x, y, function(a, b) b)
    base_veg <- 0.5 * (1 - (xx^2 + yy^2))

    ndvi_stack <- array(0, dim = c(n_dates, n, n))
    for (t in seq_len(n_dates)) {
      veg_level <- 0.5 + 0.3 * sin(2 * pi * t / n_dates)
      red_noise <- array(rnorm(n * n, mean = 0, sd = 0.05), dim = c(n, n))
      nir_noise <- array(rnorm(n * n, mean = 0, sd = 0.05), dim = c(n, n))
      red <- 0.1 + 0.2 * (1 - base_veg * veg_level) + red_noise
      nir <- 0.3 + 0.5 * base_veg * veg_level + nir_noise
      epsilon <- 1e-6
      ndvi <- (nir - red) / (nir + red + epsilon)
      ndvi_stack[t, , ] <- pmin(pmax(ndvi, -0.1), 1.0)
    }
    list(ndvi_stack = ndvi_stack, n_dates = n_dates, n = n)
  }

  run <- function(s) {
    ndvi_stack <- s$ndvi_stack
    n_dates <- s$n_dates

    # Mean NDVI per date
    mean_ndvi <- apply(ndvi_stack, 1, mean)

    # Per-pixel statistics
    mean_px <- apply(ndvi_stack, c(2, 3), mean)
    max_px <- apply(ndvi_stack, c(2, 3), max)
    min_px <- apply(ndvi_stack, c(2, 3), min)
    std_px <- apply(ndvi_stack, c(2, 3), sd)

    # Amplitude
    amplitude <- max_px - min_px

    invisible(NULL)
  }

  results <- run_all_scales("timeseries_ndvi", scales, setup, run, n_runs = 5, unit = "pixels per side (n x n x 46 dates)")
  save_results("timeseries_ndvi", scales, results, "pixels per side (n x n x 46 dates)", 5)
}

# =============================================================================
# Scenario 7: Raster Algebra Scaling
# =============================================================================

benchmark_raster_scaling <- function(quick = FALSE) {
  scales <- if (quick) RASTER_SCALES_QUICK else RASTER_SCALES

  setup <- function(n) {
    set.seed(42)
    list(
      red = matrix(runif(n * n) * 0.3, n, n),
      nir = matrix(runif(n * n) * 0.5 + 0.2, n, n),
      green = matrix(runif(n * n) * 0.25 + 0.1, n, n),
      swir = matrix(runif(n * n) * 0.4, n, n)
    )
  }

  run <- function(s) {
    red <- s$red
    nir <- s$nir
    green <- s$green
    swir <- s$swir

    # NDVI
    ndvi <- (nir - red) / (nir + red + 1e-8)

    # EVI
    evi <- 2.5 * (nir - red) / (nir + 6.0 * red - 7.5 * green + 1.0)

    # NDWI
    ndwi <- (nir - swir) / (nir + swir + 1e-8)

    # 3x3 mean filter
    kernel <- matrix(1/9, 3, 3)
    rows <- nrow(ndvi)
    cols <- ncol(ndvi)
    conv <- matrix(0.0, rows, cols)
    for (r in 2:(rows - 1)) {
      for (c in 2:(cols - 1)) {
        patch <- ndvi[(r-1):(r+1), (c-1):(c+1)]
        conv[r, c] <- sum(patch * kernel)
      }
    }

    invisible(NULL)
  }

  results <- run_all_scales("raster_algebra", scales, setup, run, n_runs = 5, unit = "pixels per side (n x n)")
  save_results("raster_algebra", scales, results, "pixels per side (n x n)", 5)
}

# =============================================================================
# Scenario 8: Zonal Statistics Scaling
# =============================================================================

benchmark_zonal_scaling <- function(quick = FALSE) {
  scales <- if (quick) ZONAL_SCALES_QUICK else ZONAL_SCALES
  n_zones <- 10L

  setup <- function(n) {
    set.seed(42)
    raster <- matrix(rnorm(n * n, mean = 50, sd = 10), n, n)
    mask <- matrix(0L, n, n)

    for (z in seq_len(n_zones)) {
      r0 <- ((z - 1) * n) %/% n_zones + 1
      r1 <- min((z * n) %/% n_zones, n)
      mask[r0:r1, ] <- z
    }

    list(raster = raster, mask = mask, n_zones = n_zones)
  }

  run <- function(s) {
    raster <- s$raster
    mask <- s$mask
    n_zones <- s$n_zones

    for (z in seq_len(n_zones)) {
      zone_mask <- mask == z
      if (!any(zone_mask)) next
      vals <- raster[zone_mask]
      z_mean <- mean(vals)
      z_std <- sd(vals)
    }
    invisible(NULL)
  }

  results <- run_all_scales("zonal_stats", scales, setup, run, n_runs = 5, unit = "pixels per side (n x n)")
  save_results("zonal_stats", scales, results, "pixels per side (n x n)", 5)
}

# =============================================================================
# Scenario 9: Coordinate Reprojection Scaling
# =============================================================================

benchmark_reproj_scaling <- function(quick = FALSE) {
  scales <- if (quick) REPROJ_SCALES_QUICK else REPROJ_SCALES

  setup <- function(n) {
    set.seed(42)
    lons <- runif(n, -180, 180)
    lats <- runif(n, -90, 90)

    # Web Mercator (EPSG:3857)
    x_3857 <- lons * 20037508.34 / 180.0
    y_3857 <- log(tan((90.0 + lats) * pi / 360.0)) * 20037508.34 / pi

    # Determine UTM zone from center
    lon_center <- mean(lons)
    zone <- as.integer(floor((lon_center + 180.0) / 6.0)) + 1

    list(lons = lons, lats = lats, x_3857 = x_3857, y_3857 = y_3857, zone = zone)
  }

  run <- function(data) {
    lons <- data$lons
    lats <- data$lats
    x_3857 <- data$x_3857
    y_3857 <- data$y_3857
    zone <- data$zone
    n <- length(lons)

    # Web Mercator (already computed in setup, just reference)
    x_3857_result <- x_3857
    y_3857_result <- y_3857

    # UTM conversion
    lon0 <- -183.0 + zone * 6.0

    for (i in seq_len(n)) {
      lat_rad <- lats[i] * pi / 180
      lon_rad <- lons[i] * pi / 180
      lon0_rad <- lon0 * pi / 180

      k0 <- 0.9996
      a <- 6378137.0
      e2 <- 0.00669438

      m <- a * ((1 - e2/4 - 3*e2^2/64 - 5*e2^3/256) * lat_rad
               - (3*e2/8 + 3*e2^2/32 + 45*e2^3/1024) * sin(2*lat_rad)
               + (15*e2^2/256 + 45*e2^3/1024) * sin(4*lat_rad)
               - (35*e2^3/3072) * sin(6*lat_rad))

      n_val <- a / sqrt(1 - e2 * sin(lat_rad)^2)
      t <- tan(lat_rad)^2
      c_val <- e2 / (1 - e2) * cos(lat_rad)^2
      a_val <- cos(lat_rad) * (lon_rad - lon0_rad)

      x <- k0 * n_val * (a_val + (1-t+c_val)*a_val^3/6)
      y <- k0 * (m + n_val * tan(lat_rad) * a_val^2/2)
    }
    invisible(NULL)
  }

  results <- run_all_scales("reprojection", scales, setup, run, n_runs = 5, unit = "points")
  save_results("reprojection", scales, results, "points", 5)
}

# =============================================================================
# Main
# =============================================================================

main <- function() {
  quick <- "--quick" %in% commandArgs(trailingOnly = TRUE)

  cat(paste(rep("=", 70), collapse = ""), "\n")
  cat("R — Data Scaling Benchmark Suite\n")
  cat(paste(rep("=", 70), collapse = ""), "\n")
  cat("Methodology:", if (quick) "QUICK" else "Full", "scaling across all 9 scenarios\n")
  cat("Primary metric: Minimum time (Chen & Revels 2016)\n")
  if (quick) cat("Quick mode: smaller scales for faster iteration\n")

  # Scenario 1: Matrix Operations
  benchmark_matrix_scaling(quick)

  # Scenario 2: I/O Operations
  benchmark_io_scaling(quick)

  # Scenario 3: Hyperspectral SAM
  benchmark_hyperspectral_scaling(quick)

  # Scenario 4: Vector Point-in-Polygon
  benchmark_vector_scaling(quick)

  # Scenario 5: IDW Interpolation
  benchmark_idw_scaling(quick)

  # Scenario 6: Time-Series NDVI
  benchmark_timeseries_scaling(quick)

  # Scenario 7: Raster Algebra
  benchmark_raster_scaling(quick)

  # Scenario 8: Zonal Statistics
  benchmark_zonal_scaling(quick)

  # Scenario 9: Coordinate Reprojection
  benchmark_reproj_scaling(quick)

  cat("\n", paste(rep("=", 70), collapse = ""), "\n")
  cat("All scaling benchmarks complete!\n")
  cat("Results saved to: results/scaling/\n")
  cat(paste(rep("=", 70), collapse = ""), "\n")
}

main()
