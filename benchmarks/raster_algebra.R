#!/usr/bin/env Rscript
# =============================================================================
# SCENARIO E: Raster Algebra & Band Math - R Implementation
# Tests: Band arithmetic, NDVI calculation, spectral indices
# =============================================================================

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

script_dir <- dirname(normalizePath(commandArgs(trailingOnly = FALSE)[grep("--file=", commandArgs(trailingOnly = FALSE))]))
script_dir <- sub("^--file=", "", script_dir)
OUTPUT_DIR <- "validation"
RESULTS_DIR <- "results"

source(file.path(PROJECT_ROOT, "benchmarks", "common_hash.R"))

suppressPackageStartupMessages({
  library(terra)
  library(jsonlite)
  library(digest)
})

load_cuprite_bands <- function(data_mode = "auto") {
  data_dir <- file.path(PROJECT_ROOT, "data")
  mat_path <- file.path(data_dir, "Cuprite.mat")

  if (data_mode == "synthetic") {
    set.seed(42)
    shape <- c(512, 614)
    return(list(
      green = matrix(runif(prod(shape)) * 1000, nrow = shape[1], ncol = shape[2]),
      red = matrix(runif(prod(shape)) * 800, nrow = shape[1], ncol = shape[2]),
      nir = matrix(runif(prod(shape)) * 2000, nrow = shape[1], ncol = shape[2]),
      swir = matrix(runif(prod(shape)) * 1500, nrow = shape[1], ncol = shape[2]),
      shape = c(4, shape)
    ), "synthetic")
  }

  result <- tryCatch({
    if (file.exists(mat_path)) {
      mat_data <- R.matlab::readMat(mat_path)
      data <- mat_data[[1]]
      green <- data[, , 31]
      red <- data[, , 51]
      nir <- data[, , 71]
      swir <- data[, , 91]
      cat(sprintf("  ✓ Loaded real Cuprite data: %s\n", paste(dim(data), collapse = " x ")))
      return(list(
        green = green, red = red, nir = nir, swir = swir, shape = dim(data)
      ), "real")
    } else if (data_mode == "real") {
      cat("  x Cuprite.mat not found\n")
      quit(status = 1)
    }
    stop("file not found")
  }, error = function(e) {
    cat("Warning: Could not load Cuprite data:", conditionMessage(e), "\n")
    if (data_mode == "real") {
      cat("  x Real data required but unavailable\n")
      quit(status = 1)
    }
    cat("  → Using synthetic data instead...\n")
    set.seed(42)
    shape <- c(512, 614)
    return(list(
      green = matrix(runif(prod(shape)) * 1000, nrow = shape[1], ncol = shape[2]),
      red = matrix(runif(prod(shape)) * 800, nrow = shape[1], ncol = shape[2]),
      nir = matrix(runif(prod(shape)) * 2000, nrow = shape[1], ncol = shape[2]),
      swir = matrix(runif(prod(shape)) * 1500, nrow = shape[1], ncol = shape[2]),
      shape = c(4, shape)
    ), "synthetic")
  })
}

benchmark_ndvi <- function(nir, red) {
  numerator <- nir - red
  denominator <- nir + red
  ndvi <- ifelse(denominator != 0, numerator / denominator, 0)
  return(ndvi)
}

benchmark_band_arithmetic <- function(green, red, nir, swir) {
  results <- list()
  results$sum <- green + red + nir + swir
  results$difference <- nir - red
  results$ratio <- nir / pmax(red, .Machine$double.eps)
  blue <- green * 0.8
  results$evi <- 2.5 * (nir - red) / (nir + 6*red - 7.5*blue + 1)
  L <- 0.5
  results$savi <- ((nir - red) / (nir + red + L)) * (1 + L)
  results$ndwi <- (green - nir) / (green + nir)
  results$nbr <- (nir - swir) / (nir + swir)
  return(results)
}

run_benchmark <- function(func, runs = 10, warmup = 2) {
  for (i in 1:warmup) {
    invisible(func())
  }
  
  times <- numeric(runs)
  result <- NULL
  for (i in 1:runs) {
    t_start <- proc.time()
    result <- func()
    t_end <- proc.time()
    times[i] <- (t_end - t_start)["elapsed"]
  }
  
  list(times = times, result = result)
}

run_raster_algebra_benchmark <- function(data_mode = "auto") {
  cat(strrep("=", 70), "\n")
  cat("R - Scenario E: Raster Algebra & Band Math\n")
  cat(strrep("=", 70), "\n")

  cat("\n[1/4] Loading hyperspectral data...\n")
  bands_result <- load_cuprite_bands(data_mode)
  bands <- bands_result[[1]]
  data_source <- bands_result[[2]]
  cat(sprintf("  ✓ Loaded %d bands, shape: %d x %d (%d pixels)\n",
              bands$shape[1], bands$shape[2], bands$shape[3], 
              bands$shape[2] * bands$shape[3]))
  
  results <- list()
  all_hashes <- character(0)
  
  cat("\n[2/4] Testing NDVI calculation...\n")
  
  ndvi_task <- function() {
    benchmark_ndvi(bands$nir, bands$red)
  }
  
  bench_result <- run_benchmark(ndvi_task, 10, 2)
  times <- bench_result$times
  ndvi_result <- bench_result$result
  ndvi_hash <- generate_hash(ndvi_result)
  all_hashes <- c(all_hashes, ndvi_hash)
  
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", min(times)))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", mean(times), sd(times)))
  cat(sprintf("  ✓ Hash: %s\n", ndvi_hash))
  
  results$ndvi <- list(
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    median_time_s = median(times),
    max_time_s = max(times),
    times = as.list(times),
    validation_hash = ndvi_hash
  )
  
  cat("\n[3/4] Testing band arithmetic...\n")
  
  band_math_task <- function() {
    benchmark_band_arithmetic(bands$green, bands$red, bands$nir, bands$swir)
  }
  
  bench_result <- run_benchmark(band_math_task, 10, 2)
  times <- bench_result$times
  indices_result <- bench_result$result
  indices_hash <- generate_hash(unlist(indices_result))
  all_hashes <- c(all_hashes, indices_hash)
  
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", min(times)))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", mean(times), sd(times)))
  cat(sprintf("  ✓ Hash: %s\n", indices_hash))
  
  results$band_arithmetic <- list(
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    median_time_s = median(times),
    max_time_s = max(times),
    times = as.list(times),
    validation_hash = indices_hash
  )
  
  cat("\n[4/4] Testing 3x3 convolution...\n")
  
  dim_nir <- dim(bands$nir)
  nir_rast <- terra::rast(nrows = dim_nir[1], ncols = dim_nir[2], vals = as.numeric(bands$nir))
  
  conv_task <- function() {
    terra::focal(nir_rast, w = matrix(1/9, 3, 3), fun = "mean", fillvalue = 0)
  }
  
   bench_result <- run_benchmark(conv_task, 10, 2)
  times <- bench_result$times
  conv_result <- bench_result$result
  conv_hash <- generate_hash(as.matrix(conv_result))
  all_hashes <- c(all_hashes, conv_hash)
  
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", min(times)))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", mean(times), sd(times)))
  cat(sprintf("  ✓ Hash: %s\n", conv_hash))
  
  results$convolution_3x3 <- list(
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    median_time_s = median(times),
    max_time_s = max(times),
    times = as.list(times),
    validation_hash = conv_hash
  )
  
  cat("\n", strrep("=", 70), "\n")
  cat("SAVING RESULTS...\n")
  cat(strrep("=", 70), "\n")
  
  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)
  
  output_data <- list(
    language = "r",
    scenario = "raster_algebra",
    data_source = data_source,
    data_description = if (data_source == "real") "Cuprite.mat" else "synthetic 4×512×614",
    data_shape = bands$shape,
    results = results,
    all_hashes = all_hashes,
    combined_hash = generate_hash(all_hashes)
  )
  
  write_json(
    output_data,
    file.path(OUTPUT_DIR, "raster_algebra_r_results.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )
  
  cat("✓ Results saved\n")
  cat(sprintf("✓ Combined validation hash: %s\n", output_data$combined_hash))
  
  cat("\n", strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")
  
  return(output_data)
}

# Parse CLI args
args <- commandArgs(trailingOnly = TRUE)
data_mode <- "auto"
for (i in seq_along(args)) {
  if (args[i] == "--data" && i < length(args)) {
    data_mode <- args[i + 1]
  }
}
run_raster_algebra_benchmark(data_mode)
