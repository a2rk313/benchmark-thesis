#!/usr/bin/env Rscript
################################################################################
# SCENARIO A.2: Hyperspectral Spectral Angle Mapper - R Implementation
################################################################################
# Task: SAM classification on 224-band hyperspectral imagery
# Dataset: NASA AVIRIS Cuprite (224 bands, freely available)
# Metrics: terra C++ efficiency, chunked processing, memory management
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
  library(terra)
  library(R.matlab)
  library(jsonlite)
  library(digest)
})

RUNS <- 5
WARMUP <- 2

spectral_angle_mapper <- function(pixel_matrix, reference_spectrum) {
  epsilon <- 1e-8
  dot_products <- pixel_matrix %*% reference_spectrum
  pixel_norms <- sqrt(rowSums(pixel_matrix^2))
  ref_norm <- sqrt(sum(reference_spectrum^2))
  cos_angles <- dot_products / (pixel_norms * ref_norm + epsilon)
  cos_angles <- pmin(pmax(cos_angles, -1), 1)
  angles <- acos(cos_angles)
  return(as.vector(angles))
}

process_chunked <- function(data, reference_spectrum, chunk_size = 256) {
  n_bands <- dim(data)[1]
  n_rows <- dim(data)[2]
  n_cols <- dim(data)[3]
  
  sum_angles <- 0.0
  sum_sq_angles <- 0.0
  sum_min <- Inf
  sum_max <- -Inf
  count <- 0
  pixels_processed <- 0
  chunks_processed <- 0
  
  for (row_start in seq(1, n_rows, by = chunk_size)) {
    for (col_start in seq(1, n_cols, by = chunk_size)) {
      row_end <- min(row_start + chunk_size - 1, n_rows)
      col_end <- min(col_start + chunk_size - 1, n_cols)
      
      chunk <- data[, row_start:row_end, col_start:col_end, drop = FALSE]
      chunk_rows <- row_end - row_start + 1
      chunk_cols <- col_end - col_start + 1
      
      dim(chunk) <- c(n_bands, chunk_rows * chunk_cols)
      pixel_matrix <- t(chunk)
      
      if (nrow(pixel_matrix) > 0) {
        sam_angles <- spectral_angle_mapper(pixel_matrix, reference_spectrum)
        chunk_sum <- sum(sam_angles)
        chunk_sum_sq <- sum(sam_angles^2)
        sum_angles <- sum_angles + chunk_sum
        sum_sq_angles <- sum_sq_angles + chunk_sum_sq
        sum_min <- min(sum_min, min(sam_angles))
        sum_max <- max(sum_max, max(sam_angles))
        count <- count + length(sam_angles)
        pixels_processed <- pixels_processed + length(sam_angles)
      }
      
      chunks_processed <- chunks_processed + 1
    }
  }
  
  mean_angle <- if (count > 0) sum_angles / count else 0
  std_angle <- if (count > 0) sqrt(sum_sq_angles / count - mean_angle^2) else 0
  
  list(
    mean_sam = mean_angle,
    std_sam = std_angle,
    min_sam = sum_min,
    max_sam = sum_max,
    pixels_processed = pixels_processed,
    chunks_processed = chunks_processed
  )
}

load_synthetic_hsi <- function(n_bands = 224, n_rows = 512, n_cols = 614) {
  cat("  Generating synthetic HSI data...\n")
  set.seed(42)
  x <- seq(0, 4 * pi, length.out = n_cols)
  y <- seq(0, 4 * pi, length.out = n_rows)
  xx <- outer(y, x, function(y, x) matrix(x, nrow = length(y), ncol = length(x), byrow = TRUE))
  yy <- outer(y, x, function(y, x) matrix(y, nrow = length(y), ncol = length(x)))
  signal <- 0.3 * sin(xx + yy) + 0.2 * sin(2 * xx - yy)
  data <- array(0, dim = c(n_bands, n_rows, n_cols))
  spectral_pattern <- seq(0.8, 1.2, length.out = n_bands)
  for (b in 1:n_bands) {
    noise <- matrix(rnorm(n_rows * n_cols) * 100, nrow = n_rows, ncol = n_cols)
    data[b, , ] <- (signal + noise) * spectral_pattern[b] * 100 + 1000
  }
  cat(sprintf("  + Synthetic HSI: %d bands × %d × %d\n", n_bands, n_rows, n_cols))
  return(data)
}

load_hsi_data <- function(data_mode) {
  if (data_mode == "synthetic") {
    return(list(data = load_synthetic_hsi(), source = "synthetic"))
  }
  hsi_path <- file.path(DATA_DIR, "Cuprite.mat")
  if (file.exists(hsi_path) || data_mode == "real") {
    result <- tryCatch({
      cat(sprintf("  Loading MAT file: %s\n", hsi_path))
      mat_data <- R.matlab::readMat(hsi_path)
      data_key <- names(mat_data)[1]
      raw_data <- mat_data[[data_key]]
      if (dim(raw_data)[1] == 512 && dim(raw_data)[3] == 224) {
        data <- aperm(raw_data, c(3, 1, 2))
        data <- data[1:224, , ]
      } else {
        data <- raw_data
      }
      cat(sprintf("  + Real HSI: %d bands × %d × %d\n", dim(data)[1], dim(data)[2], dim(data)[3]))
      list(data = data, source = "real")
    }, error = function(e) {
      if (data_mode == "real") {
        cat(sprintf("  x Real data load failed: %s\n", e$message))
        quit(status = 1)
      }
      cat(sprintf("  - Real data unavailable (%s), using synthetic\n", e$message))
      list(data = NULL, source = NULL)
    })
    if (!is.null(result$data)) return(result)
  }
  return(list(data = load_synthetic_hsi(), source = "synthetic"))
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
  cat("R - Scenario A.2: Hyperspectral SAM\n")
  cat(strrep("=", 70), "\n")

  cat("\n[1/5] Initializing...\n")
  n_bands <- 224
  reference_spectrum <- seq(0.1, 0.9, length.out = n_bands)
  reference_spectrum <- reference_spectrum / sqrt(sum(reference_spectrum^2))
  cat(sprintf("  ✓ Reference spectrum: %d bands\n", n_bands))
  ref_hash <- substr(digest(reference_spectrum, algo = "sha256"), 1, 16)
  cat(sprintf("  ✓ Reference spectrum hash: %s\n", ref_hash))

  cat("\n[2/5] Opening hyperspectral dataset...\n")
  hsi_result <- load_hsi_data(data_mode)
  data <- hsi_result$data
  data_source <- hsi_result$source
  
  n_bands <- dim(data)[1]
  n_rows <- dim(data)[2]
  n_cols <- dim(data)[3]
  cat(sprintf("  ✓ Dataset shape: %d bands × %d × %d pixels\n", n_bands, n_rows, n_cols))

  cat(sprintf("\n[3/5] Running SAM classification (%d runs, %d warmup)...\n", RUNS, WARMUP))
  
  task <- function() {
    process_chunked(data, reference_spectrum)
  }
  
  for (i in seq_len(WARMUP)) {
    task()
  }
  
  times <- numeric(RUNS)
  result <- NULL
  for (i in seq_len(RUNS)) {
    t_start <- Sys.time()
    result <- task()
    t_end <- Sys.time()
    times[i] <- as.numeric(difftime(t_end, t_start, units = "secs"))
  }
  
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", min(times)))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", mean(times), sd(times)))
  
  cat("\n[4/5] SAM classification results...\n")
  cat(sprintf("  ✓ Mean SAM angle: %.6f rad (%.2f°)\n", result$mean_sam, result$mean_sam * 180 / pi))
  cat(sprintf("  ✓ Std SAM angle: %.6f rad\n", result$std_sam))
  cat(sprintf("  ✓ Min SAM angle: %.6f rad\n", result$min_sam))
  cat(sprintf("  ✓ Max SAM angle: %.6f rad\n", result$max_sam))
  cat(sprintf("  ✓ Processed %d chunks (%s pixels)\n", result$chunks_processed, format(result$pixels_processed, big.mark = ",")))
  
  cat("\n[5/5] Validation and export...\n")
  hash_input <- c(result$mean_sam, result$std_sam, result$min_sam, result$max_sam)
  validation_hash <- generate_hash(hash_input)
  cat(sprintf("  ✓ Validation hash: %s\n", validation_hash))
  
  results <- list(
    language = "r",
    scenario = "hyperspectral_sam",
    data_source = data_source,
    data_description = if (data_source == "real") "Cuprite.mat" else sprintf("synthetic %dx%dx%d", n_bands, n_rows, n_cols),
    pixels_processed = result$pixels_processed,
    chunks_processed = result$chunks_processed,
    n_bands = n_bands,
    mean_sam_rad = result$mean_sam,
    std_sam_rad = result$std_sam,
    min_sam_rad = result$min_sam,
    max_sam_rad = result$max_sam,
    mean_sam_deg = result$mean_sam * 180 / pi,
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    max_time_s = max(times),
    times = times,
    validation_hash = validation_hash,
    reference_hash = ref_hash
  )
  
  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(VALIDATION_DIR, showWarnings = FALSE, recursive = TRUE)
  
  write_json(
    results,
    file.path(OUTPUT_DIR, "hsi_stream_r.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )
  write_json(
    results,
    file.path(VALIDATION_DIR, "raster_r_results.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )
  
  cat("✓ Results saved\n")
  cat(strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")
  
  return(0)
}

quit(status = main())
