#!/usr/bin/env Rscript
################################################################################
# SCENARIO C: Spatial Interpolation - R Implementation (using FNN for KD-tree)
################################################################################
# Task: Inverse Distance Weighting (IDW) interpolation on scattered points
# Dataset: 50,000 random points → 1000x1000 grid interpolation
# Metrics: Computational throughput, numerical efficiency
# Uses: FNN package for KD-tree nearest neighbor search
################################################################################

suppressPackageStartupMessages({
  library(FNN)
  library(jsonlite)
  library(digest)
})

idw_interpolation <- function(known_x, known_y, known_z, grid_x, grid_y, power = 2, nmax = 12) {
  known_points <- cbind(known_x, known_y)
  grid_points <- cbind(grid_x, grid_y)
  
  nn_result <- get.knnx(known_points, grid_points, k = nmax)
  distances <- nn_result$nn.dist
  indices <- nn_result$nn.index
  
  distances[distances < 1e-10] <- 1e-10
  
  weights <- 1.0 / (distances ^ power)
  weights_sum <- rowSums(weights)
  
  interpolated <- rowSums(weights * known_z[indices]) / weights_sum
  
  return(interpolated)
}

main <- function() {
  cat(strrep("=", 70), "\n")
  cat("R - Scenario C: Spatial Interpolation (IDW)\n")
  cat(strrep("=", 70), "\n")
  
  # ===========================================================================
  # 1. Generate synthetic scattered points
  # ===========================================================================
  cat("\n[1/4] Generating scattered point data...\n")
  
  set.seed(42)
  n_points <- 50000
  
  x <- runif(n_points, 0, 1000)
  y <- runif(n_points, 0, 1000)
  
  values <- (
    100 * sin(x / 200) * cos(y / 200) +
    50 * sin(x / 50) +
    20 * rnorm(n_points)
  )
  
  cat(sprintf("  ✓ Generated %s scattered points\n", format(n_points, big.mark = ",")))
  cat(sprintf("  ✓ Value range: [%.2f, %.2f]\n", min(values), max(values)))
  
  # ===========================================================================
  # 2. Create interpolation grid
  # ===========================================================================
  cat("\n[2/4] Creating interpolation grid...\n")
  
  grid_resolution <- 1000
  grid_x_vec <- seq(0, 1000, length.out = grid_resolution)
  grid_y_vec <- seq(0, 1000, length.out = grid_resolution)
  
  grid_x <- rep(grid_x_vec, each = length(grid_y_vec))
  grid_y <- rep(grid_y_vec, times = length(grid_x_vec))
  
  n_grid <- length(grid_x)
  
  cat(sprintf("  ✓ Grid size: %d × %d\n", grid_resolution, grid_resolution))
  cat(sprintf("  ✓ Total interpolation points: %s\n", format(n_grid, big.mark = ",")))
  
  # ===========================================================================
  # 3. Perform IDW interpolation
  # ===========================================================================
  cat("\n[3/4] Performing IDW interpolation...\n")
  
  start_time <- Sys.time()
  
  interpolated <- idw_interpolation(
    x, y, values,
    grid_x, grid_y,
    power = 2,
    nmax = 12
  )
  
  elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  cat(sprintf("  ✓ Interpolation complete in %.2f seconds\n", elapsed_time))
  cat(sprintf("  ✓ Interpolated value range: [%.2f, %.2f]\n", min(interpolated, na.rm=TRUE), max(interpolated, na.rm=TRUE)))
  
  # ===========================================================================
  # 4. Compute statistics and validate
  # ===========================================================================
  cat("\n[4/4] Computing metrics...\n")
  
  mean_value <- mean(interpolated, na.rm = TRUE)
  std_value <- sd(interpolated, na.rm = TRUE)
  median_value <- median(interpolated, na.rm = TRUE)
  
  points_per_second <- n_grid / elapsed_time
  
  cat(sprintf("  ✓ Mean interpolated value: %.2f\n", mean_value))
  cat(sprintf("  ✓ Std dev: %.2f\n", std_value))
  cat(sprintf("  ✓ Processing rate: %s grid points/second\n", format(round(points_per_second), big.mark = ",")))
  
  result_str <- sprintf("%.6f_%.6f_%.6f", mean_value, std_value, median_value)
  result_hash <- substr(digest(result_str, algo = "sha256"), 1, 16)
  
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))
  
  results <- list(
    language = "r",
    scenario = "interpolation_idw",
    n_points = n_points,
    grid_size = grid_resolution,
    total_interpolated = n_grid,
    execution_time_s = elapsed_time,
    points_per_second = points_per_second,
    mean_value = mean_value,
    std_value = std_value,
    median_value = median_value,
    validation_hash = result_hash
  )
  
  dir.create("validation", showWarnings = FALSE)
  write_json(
    results,
    "validation/interpolation_r_results.json",
    pretty = TRUE,
    auto_unbox = TRUE
  )
  
  cat("\n  ✓ Results saved to validation/interpolation_r_results.json\n")
  cat(strrep("=", 70), "\n")
  
  return(0)
}

quit(status = main())
