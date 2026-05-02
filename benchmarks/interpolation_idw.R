#!/usr/bin/env Rscript
################################################################################
# SCENARIO C: Spatial Interpolation – R (IDW with FNN, synthetic only)
################################################################################
# Task: Inverse Distance Weighting (IDW) interpolation on scattered points
# Dataset: 50,000 random points → 1000×1000 grid interpolation
# Metrics: Computational throughput, numerical efficiency
# Methodology: Chen & Revels (2016) - min time as primary estimator
################################################################################

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
OUTPUT_DIR <- file.path(PROJECT_ROOT, "results")
VALIDATION_DIR <- file.path(PROJECT_ROOT, "validation")

source(file.path(PROJECT_ROOT, "benchmarks", "common_hash.R"))

suppressPackageStartupMessages({
  library(FNN)
  library(jsonlite)
  library(digest)
})

RUNS <- 5
WARMUP <- 2

idw_interpolation <- function(points, values, grid_x, grid_y,
                              power = 2, neighbors = 12) {
  grid_pts <- cbind(as.vector(grid_x), as.vector(grid_y))
  nn <- get.knnx(points, grid_pts, k = neighbors)
  dists <- pmax(nn$nn.dist, 1e-10)
  idx <- nn$nn.index
  weights <- 1 / (dists ^ power)
  weights <- weights / rowSums(weights)
  interpolated <- rowSums(weights * matrix(values[idx], ncol = neighbors))
  matrix(interpolated, nrow = nrow(grid_x), ncol = ncol(grid_x))
}

generate_synthetic_points <- function(n = 50000) {
  set.seed(42)
  x <- runif(n, 0, 1000)
  y <- runif(n, 0, 1000)
  value <- 100 * sin(x / 200) * cos(y / 200) +
           50 * sin(x / 50) +
           20 * rnorm(n)
  data.frame(x = x, y = y, value = value)
}

load_idw_data <- function(data_mode) {
  csv_path <- file.path(DATA_DIR, "synthetic", "idw_points_50k.csv")
  if (data_mode == "synthetic") {
    cat("  Generating synthetic IDW points...\n")
    set.seed(42)
    n <- 50000
    x <- runif(n, 0, 1000)
    y <- runif(n, 0, 1000)
    value <- 100 * sin(x / 200 + 10) * cos(y / 200) + 50 * sin(x / 50) + 20 * rnorm(n)
    return(list(points_df = data.frame(x = x, y = y, value = value), source = "synthetic"))
  }
  if (file.exists(csv_path) || data_mode == "real") {
    result <- tryCatch({
      points_df <- read.csv(csv_path)
      cat(sprintf("  ✓ Loaded %d points from shared CSV\n", nrow(points_df)))
      list(points_df = points_df, source = "real")
    }, error = function(e) {
      if (data_mode == "real") {
        cat(sprintf("  x Real data load failed: %s\n", e$message))
        quit(status = 1)
      }
      cat(sprintf("  - CSV unavailable (%s), using synthetic\n", e$message))
      list(points_df = NULL, source = NULL)
    })
    if (!is.null(result$points_df)) return(result)
  }
  cat("  Generating synthetic IDW points...\n")
  set.seed(42)
  n <- 50000
  x <- runif(n, 0, 1000)
  y <- runif(n, 0, 1000)
  value <- 100 * sin(x / 200 + 10) * cos(y / 200) + 50 * sin(x / 50) + 20 * rnorm(n)
  return(list(points_df = data.frame(x = x, y = y, value = value), source = "synthetic"))
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  data_mode <- "auto"
  for (i in seq_along(args)) {
    if (args[i] == "--data" && i < length(args)) {
      data_mode <- args[i + 1]
    }
  }

  cat(strrep("=", 70), "\n")
  cat("R - Scenario C: Spatial Interpolation (IDW with FNN)\n")
  cat(strrep("=", 70), "\n")

  cat("\n[1/3] Loading scattered point data...\n")
  idw_data <- load_idw_data(data_mode)
  points_df <- idw_data$points_df
  data_source <- idw_data$source
  cat(sprintf("  ✓ %d points loaded (%s)\n", nrow(points_df), data_source))
  points <- as.matrix(points_df[, c("x", "y")])
  values <- points_df$value

  cat("\n[2/3] Creating interpolation grid...\n")
  grid_res <- 1000
  grid_x <- matrix(seq(0, 1000, length.out = grid_res),
                   nrow = grid_res, ncol = grid_res, byrow = TRUE)
  grid_y <- matrix(seq(0, 1000, length.out = grid_res),
                   nrow = grid_res, ncol = grid_res, byrow = FALSE)
  cat(sprintf("  ✓ Grid size: %d × %d\n", grid_res, grid_res))
  cat(sprintf("  ✓ Total interpolation points: %s\n",
              format(grid_res^2, big.mark = ",")))

  cat(sprintf("\n[3/3] Performing IDW interpolation (%d runs, %d warmup)...\n", RUNS, WARMUP))
  
  task <- function() {
    idw_interpolation(points, values, grid_x, grid_y, power = 2, neighbors = 12)
  }
  
  for (i in seq_len(WARMUP)) {
    task()
  }
  
  times <- numeric(RUNS)
  interpolated <- NULL
  for (i in seq_len(RUNS)) {
    t_start <- Sys.time()
    interpolated <- task()
    t_end <- Sys.time()
    times[i] <- as.numeric(difftime(t_end, t_start, units = "secs"))
  }
  
  points_per_second <- (grid_res^2) / min(times)
  
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", min(times)))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", mean(times), sd(times)))
  cat(sprintf("  ✓ Processing rate: %s grid points/second\n",
              format(round(points_per_second), big.mark = ",")))

  cat("\nComputing domain statistics...\n")
  mean_val <- mean(interpolated, na.rm = TRUE)
  std_val <- sd(interpolated, na.rm = TRUE)
  med_val <- median(interpolated, na.rm = TRUE)
  cat(sprintf("  ✓ Mean: %.2f, Std: %.2f, Median: %.2f\n", mean_val, std_val, med_val))

  result_hash <- generate_hash(interpolated)
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))

  results <- list(
    language = "r",
    scenario = "interpolation_idw",
    data_source = data_source,
    data_description = if (data_source == "real") "idw_points_50k.csv" else "synthetic 50K points (seed 42)",
    n_points = nrow(points_df),
    grid_size = grid_res,
    total_interpolated = grid_res^2,
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    max_time_s = max(times),
    times = times,
    points_per_second = points_per_second,
    mean_value = mean_val,
    std_value = std_val,
    median_value = med_val,
    validation_hash = result_hash
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(VALIDATION_DIR, showWarnings = FALSE, recursive = TRUE)
  
  write_json(results, file.path(OUTPUT_DIR, "interpolation_idw_r.json"),
             pretty = TRUE, auto_unbox = TRUE)
  write_json(results, file.path(VALIDATION_DIR, "interpolation_r_results.json"),
             pretty = TRUE, auto_unbox = TRUE)

  cat("\n✓ Results saved\n")
  cat(strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")
  return(0)
}

quit(status = main())
