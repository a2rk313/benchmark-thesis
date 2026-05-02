#!/usr/bin/env Rscript
################################################################################
# SCENARIO D: Time-Series NDVI Analysis - R Implementation
################################################################################
# Task: Calculate NDVI statistics across 12-month time series
# Dataset: Synthetic Landsat-like data (500x500 pixels × 12 dates × 2 bands)
# Metrics: Temporal aggregation, array operations
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
  library(jsonlite)
  library(digest)
})

RUNS <- 10
WARMUP <- 2

load_real_modis_ndvi <- function() {
  modis_dir <- file.path(DATA_DIR, "modis")
  bin_path <- file.path(modis_dir, "modis_ndvi_timeseries.bin")
  hdr_path <- file.path(modis_dir, "modis_ndvi_timeseries.hdr")
  if (file.exists(bin_path) && file.exists(hdr_path)) {
    result <- tryCatch({
      hdr <- readLines(hdr_path)
      n_rows <- n_cols <- n_bands <- 0
      for (line in hdr) {
        if (grepl("^samples", line)) n_cols <- as.integer(trimws(strsplit(line, "=")[[1]][2]))
        if (grepl("^lines", line)) n_rows <- as.integer(trimws(strsplit(line, "=")[[1]][2]))
        if (grepl("^bands", line)) n_bands <- as.integer(trimws(strsplit(line, "=")[[1]][2]))
      }
      data <- readBin(bin_path, "double", n = n_bands * n_rows * n_cols, size = 4)
      data <- array(data, dim = c(n_cols, n_rows, n_bands))
      data <- aperm(data, c(3, 2, 1))
      cat(sprintf("  ✓ Loaded real MODIS NDVI: %d × %d × %d\n", n_bands, n_rows, n_cols))
      return(data)
    }, error = function(e) {
      cat(sprintf("  ⚠ Failed to load real MODIS data: %s\n", e$message))
      return(NULL)
    })
    return(result)
  }
  return(NULL)
}

generate_synthetic_ndvi_stack <- function(n_dates = 46, height = 1200, width = 1200) {
  set.seed(42)
  x <- seq(-1, 1, length.out = width)
  y <- seq(-1, 1, length.out = height)
  xx <- outer(y, x, function(y, x) matrix(x, nrow = length(y), ncol = length(x), byrow = TRUE))
  yy <- outer(y, x, function(y, x) matrix(y, nrow = length(y), ncol = length(x)))
  base_vegetation <- 0.5 * (1 - (xx^2 + yy^2))

  ndvi_stack <- array(0, dim = c(n_dates, height, width))

  for (t in 1:n_dates) {
    vegetation_level <- 0.5 + 0.3 * sin(2 * pi * (t - 1) / n_dates)
    red_noise <- matrix(rnorm(height * width, 0, 0.05), nrow = height, ncol = width)
    nir_noise <- matrix(rnorm(height * width, 0, 0.05), nrow = height, ncol = width)
    red <- 0.1 + 0.2 * (1 - base_vegetation * vegetation_level) + red_noise
    nir <- 0.3 + 0.5 * base_vegetation * vegetation_level + nir_noise
    epsilon <- 1e-6
    ndvi <- (nir - red) / (nir + red + epsilon)
    ndvi_stack[t, , ] <- pmax(pmin(ndvi, 1.0), -0.1)
  }

  ndvi_stack
}

load_ndvi_data <- function(data_mode) {
  if (data_mode == "synthetic") {
    return(list(data = generate_synthetic_ndvi_stack(), source = "synthetic"))
  }
  data <- load_real_modis_ndvi()
  if (!is.null(data)) {
    return(list(data = data, source = "real"))
  }
  if (data_mode == "real") {
    cat("  x Real MODIS data not available\n")
    quit(status = 1)
  }
  cat("  → Using synthetic NDVI stack\n")
  return(list(data = generate_synthetic_ndvi_stack(), source = "synthetic"))
}

calculate_ndvi_statistics <- function(ndvi_stack) {
  n_dates <- dim(ndvi_stack)[1]
  height <- dim(ndvi_stack)[2]
  width <- dim(ndvi_stack)[3]

  mean_ndvi <- apply(ndvi_stack, c(2, 3), mean)
  max_ndvi <- apply(ndvi_stack, c(2, 3), max)
  min_ndvi <- apply(ndvi_stack, c(2, 3), min)

  time_index <- seq(0, n_dates - 1)
  mean_time <- mean(time_index)
  denominator <- sum((time_index - mean_time)^2)

  ndvi_trend <- matrix(0, nrow = height, ncol = width)
  for (i in 1:height) {
    for (j in 1:width) {
      pixel_series <- ndvi_stack[, i, j]
      numerator <- sum((time_index - mean_time) * (pixel_series - mean_ndvi[i, j]))
      ndvi_trend[i, j] <- numerator / denominator
    }
  }

  growing_season <- apply(ndvi_stack > 0.3, c(2, 3), sum)
  amplitude <- max_ndvi - min_ndvi

  list(mean_ndvi = mean_ndvi, ndvi_trend = ndvi_trend, amplitude = amplitude,
       growing_season = growing_season)
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
  cat("R - Scenario D: Time-Series NDVI Analysis\n")
  cat(strrep("=", 70), "\n")

  cat("\n[1/4] Loading NDVI stack...\n")
  ndvi_result <- load_ndvi_data(data_mode)
  ndvi_stack <- ndvi_result$data
  data_source <- ndvi_result$source
  n_dates <- dim(ndvi_stack)[1]; height <- dim(ndvi_stack)[2]; width <- dim(ndvi_stack)[3]
  cat(sprintf("  ✓ Stack shape: %d dates × %d × %d pixels\n", n_dates, height, width))

  cat(sprintf("\n[2/4] Running NDVI time-series analysis (%d runs, %d warmup)...\n", RUNS, WARMUP))

  task <- function() {
    calculate_ndvi_statistics(ndvi_stack)
  }

  for (i in 1:WARMUP) {
    invisible(task())
  }

  times <- numeric(RUNS)
  result <- NULL
  for (i in 1:RUNS) {
    t_start <- Sys.time()
    result <- task()
    t_end <- Sys.time()
    times[i] <- as.numeric(difftime(t_end, t_start, units = "secs"))
  }

  cat(sprintf("  ✓ Min: %.4fs (primary)\n", min(times)))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", mean(times), sd(times)))

  cat("\n[3/4] Computing domain statistics...\n")
  mean_ndvi_val <- mean(result$mean_ndvi, na.rm = TRUE)
  trend_val <- mean(result$ndvi_trend, na.rm = TRUE)
  amplitude_val <- mean(result$amplitude, na.rm = TRUE)
  growing_days <- mean(result$growing_season, na.rm = TRUE)
  cat(sprintf("  ✓ Mean NDVI: %.4f\n", mean_ndvi_val))
  cat(sprintf("  ✓ Mean trend: %.6f\n", trend_val))
  cat(sprintf("  ✓ Mean amplitude: %.4f\n", amplitude_val))
  cat(sprintf("  ✓ Avg growing season: %.1f dates\n", growing_days))

  cat("\n[4/4] Validation and export...\n")
  hash_arrays <- c(result$mean_ndvi, result$ndvi_trend, result$amplitude)
  result_hash <- generate_hash(hash_arrays)
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))

  results <- list(
    language = "r",
    scenario = "timeseries_ndvi",
    data_source = data_source,
    data_description = if (data_source == "real") "MODIS HDF" else sprintf("synthetic %d×%d×%d", n_dates, height, width),
    n_dates = n_dates,
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    median_time_s = median(times),
    max_time_s = max(times),
    times = times,
    mean_ndvi = mean_ndvi_val,
    mean_trend = trend_val,
    mean_amplitude = amplitude_val,
    avg_growing_season = growing_days,
    validation_hash = result_hash
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(VALIDATION_DIR, showWarnings = FALSE, recursive = TRUE)

  write_json(results, file.path(OUTPUT_DIR, "timeseries_ndvi_r.json"),
             pretty = TRUE, auto_unbox = TRUE)
  write_json(results, file.path(VALIDATION_DIR, "timeseries_r_results.json"),
             pretty = TRUE, auto_unbox = TRUE)

  cat("✓ Results saved\n")
  cat(strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")

  return(0)
}

quit(status = main())
