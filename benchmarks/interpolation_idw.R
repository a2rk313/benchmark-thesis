#!/usr/bin/env Rscript
################################################################################
# SCENARIO C: Spatial Interpolation - R Implementation
################################################################################
# Task: Inverse Distance Weighting (IDW) interpolation on scattered points
# Dataset: 50,000 random points → 1000x1000 grid interpolation
# Metrics: Computational throughput, numerical efficiency
################################################################################

suppressPackageStartupMessages({
  library(gstat)
  library(sp)
  library(jsonlite)
  library(digest)
})

idw_interpolation <- function(points_df, grid, power = 2, nmax = 12) {
  # Convert to spatial objects
  coordinates(points_df) <- ~x+y
  
  # Perform IDW interpolation
  idw_result <- idw(
    value ~ 1,
    locations = points_df,
    newdata = grid,
    idp = power,
    nmax = nmax
  )
  
  return(idw_result$var1.pred)
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
  
  # Random points in [0, 1000] x [0, 1000]
  x <- runif(n_points, 0, 1000)
  y <- runif(n_points, 0, 1000)
  
  # Synthetic elevation field with spatial structure
  values <- (
    100 * sin(x / 200) * cos(y / 200) +  # Large-scale pattern
    50 * sin(x / 50) +                   # Medium-scale
    20 * rnorm(n_points)                 # Noise
  )
  
  points_df <- data.frame(x = x, y = y, value = values)
  
  cat(sprintf("  ✓ Generated %s scattered points\n", format(n_points, big.mark = ",")))
  cat(sprintf("  ✓ Value range: [%.2f, %.2f]\n", min(values), max(values)))
  
  # ===========================================================================
  # 2. Create interpolation grid
  # ===========================================================================
  cat("\n[2/4] Creating interpolation grid...\n")
  
  grid_resolution <- 1000  # 1000x1000 grid
  grid_x <- seq(0, 1000, length.out = grid_resolution)
  grid_y <- seq(0, 1000, length.out = grid_resolution)
  
  grid_df <- expand.grid(x = grid_x, y = grid_y)
  coordinates(grid_df) <- ~x+y
  gridded(grid_df) <- TRUE
  
  cat(sprintf("  ✓ Grid size: %d × %d\n", grid_resolution, grid_resolution))
  cat(sprintf("  ✓ Total interpolation points: %s\n", format(grid_resolution^2, big.mark = ",")))
  
  # ===========================================================================
  # 3. Perform IDW interpolation
  # ===========================================================================
  cat("\n[3/4] Performing IDW interpolation...\n")
  
  start_time <- Sys.time()
  interpolated <- idw_interpolation(points_df, grid_df, power = 2, nmax = 12)
  elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  cat(sprintf("  ✓ Interpolation complete in %.2f seconds\n", elapsed_time))
  cat(sprintf("  ✓ Interpolated value range: [%.2f, %.2f]\n", min(interpolated, na.rm=TRUE), max(interpolated, na.rm=TRUE)))
  
  # ===========================================================================
  # 4. Compute statistics and validate
  # ===========================================================================
  cat("\n[4/4] Computing metrics...\n")
  
  # Calculate interpolation quality metrics
  mean_value <- mean(interpolated, na.rm = TRUE)
  std_value <- sd(interpolated, na.rm = TRUE)
  median_value <- median(interpolated, na.rm = TRUE)
  
  # Calculate processing rate
  points_per_second <- (grid_resolution^2) / elapsed_time
  
  cat(sprintf("  ✓ Mean interpolated value: %.2f\n", mean_value))
  cat(sprintf("  ✓ Std dev: %.2f\n", std_value))
  cat(sprintf("  ✓ Processing rate: %s grid points/second\n", format(round(points_per_second), big.mark = ",")))
  
  # Generate validation hash
  result_str <- sprintf("%.6f_%.6f_%.6f", mean_value, std_value, median_value)
  result_hash <- substr(digest(result_str, algo = "sha256"), 1, 16)
  
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))
  
  # Export results
  results <- list(
    language = "r",
    scenario = "interpolation_idw",
    n_points = n_points,
    grid_size = grid_resolution,
    total_interpolated = grid_resolution^2,
    execution_time_s = elapsed_time,
    points_per_second = points_per_second,
    mean_value = mean_value,
    std_value = std_value,
    median_value = median_value,
    validation_hash = result_hash
  )
  
  # Save results
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

# Run benchmark
quit(status = main())
