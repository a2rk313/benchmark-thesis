#!/usr/bin/env Rscript
# =============================================================================
# SCENARIO F: Zonal Statistics - R Implementation (Optimized, real‑data first)
# =============================================================================

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

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(jsonlite)
  library(digest)
})

source(file.path(PROJECT_ROOT, "benchmarks", "common_hash.R"))

OUTPUT_DIR <- "validation"
RESULTS_DIR <- "results"

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

create_rectangular_zones <- function(n_zones = 10) {
  zones <- list()
  zone_id <- 1
  lat_step <- 180.0 / n_zones
  lon_step <- 360.0 / n_zones

  for (i in 0:(n_zones - 1)) {
    for (j in 0:(n_zones - 1)) {
      min_lon <- -180.0 + j * lon_step
      max_lon <- min_lon + lon_step
      min_lat <- -90.0 + i * lat_step
      max_lat <- min_lat + lat_step

      coords <- matrix(c(
        min_lon, min_lat,
        max_lon, min_lat,
        max_lon, max_lat,
        min_lon, max_lat,
        min_lon, min_lat
      ), ncol = 2, byrow = TRUE)

      poly <- sf::st_polygon(list(coords))
      zones[[zone_id]] <- poly
      zone_id <- zone_id + 1
    }
  }

  sf::st_sfc(zones, crs = "EPSG:4326")
}

# ---- Fast mask creation with terra::rasterize ----
rasterize_polygons_to_mask <- function(zones_sfc, rows, cols) {
  zones_vect <- vect(zones_sfc)
  zones_vect$zone_id <- 1:nrow(zones_vect)

  r_template <- rast(
    nrows = rows, ncols = cols,
    xmin = -180, xmax = 180,
    ymin = -90, ymax = 90,
    crs = "EPSG:4326"
  )

  mask_rast <- rasterize(zones_vect, r_template, field = "zone_id", background = 0)
  mask <- matrix(values(mask_rast), nrow = rows, ncol = cols, byrow = TRUE)
  storage.mode(mask) <- "integer"
  return(mask)
}

vectorized_zonal_stats <- function(raster_matrix, mask_matrix) {
  unique_zones <- sort(unique(c(mask_matrix)))
  unique_zones <- unique_zones[unique_zones > 0]

  means <- numeric()
  stds <- numeric()
  sums <- numeric()
  counts <- integer()

  for (zone_id in unique_zones) {
    values <- raster_matrix[mask_matrix == zone_id]
    if (length(values) > 0) {
      means <- c(means, mean(values))
      stds <- c(stds, sd(values))
      sums <- c(sums, sum(values))
      counts <- c(counts, length(values))
    } else {
      means <- c(means, 0.0)
      stds <- c(stds, 0.0)
      sums <- c(sums, 0.0)
      counts <- c(counts, 0)
    }
  }

  list(
    means = means,
    stds = stds,
    sums = sums,
    counts = counts,
    zones = unique_zones
  )
}

run_zonal_stats_benchmark <- function() {
  cat(strrep("=", 70), "\n")
  cat("R - Scenario F: Zonal Statistics\n")
  cat(strrep("=", 70), "\n")

  rows <- 600
  cols <- 600
  n_zones <- 10

  args <- commandArgs(trailingOnly = TRUE)
  data_mode <- "auto"  # default: try real, fallback synthetic
  if ("--data" %in% args) {
    idx <- which(args == "--data")
    if (length(idx) > 0 && idx < length(args)) {
      data_mode <- args[idx + 1]
    }
  }

  raster_matrix <- NULL
  data_source <- "synthetic"

  # --- Try loading real NLCD data (identical logic as Julia) ---
  if (data_mode %in% c("auto", "real")) {
    nlcd_paths <- c(
      file.path(PROJECT_ROOT, "data", "nlcd", "nlcd_landcover_large.bin"),
      file.path(PROJECT_ROOT, "data", "nlcd", "nlcd_landcover.bin")
    )
    for (path in nlcd_paths) {
      if (file.exists(path)) {
        hdr_path <- sub("\\.bin$", ".hdr", path)
        if (file.exists(hdr_path)) {
          hdr_lines <- readLines(hdr_path)
          r_line <- grep("^samples", hdr_lines, value = TRUE)
          l_line <- grep("^lines", hdr_lines, value = TRUE)
          if (length(r_line) > 0 && length(l_line) > 0) {
            cols <- as.integer(sub(".*= *", "", r_line))
            rows <- as.integer(sub(".*= *", "", l_line))
            con <- file(path, "rb")
            # NLCD .bin is typically unsigned 8‑bit, stored as raw bytes.
            # Julia reads as Matrix{UInt8} – we replicate that here.
            raw_data <- readBin(con, "raw", n = rows * cols)
            close(con)
            if (length(raw_data) == rows * cols) {
              raster_matrix <- matrix(as.numeric(raw_data), nrow = rows, ncol = cols)
              storage.mode(raster_matrix) <- "double"
              data_source <- "real"
              cat(sprintf("\n[1/4] Loaded real NLCD land cover: %s (%dx%d)\n", path, rows, cols))
              break
            }
          }
        }
      }
    }
    if (is.null(raster_matrix) && data_mode == "real") {
      cat("  x Real NLCD data not found or unreadable\n")
      quit(status = 1)
    }
  }

  # Fallback to synthetic (identical to Julia/Python)
  if (is.null(raster_matrix)) {
    set.seed(42)
    raster_vals <- runif(rows * cols) * 3000
    raster_matrix <- matrix(raster_vals, nrow = rows, ncol = cols)
    cat(sprintf("\n[1/4] Created synthetic raster: %d x %d cells\n", rows, cols))
  }

  cat("\n[2/4] Creating rectangular polygon zones (consistent with Python/Julia)...\n")
  zones_sfc <- create_rectangular_zones(n_zones)
  cat(sprintf("  ✓ Created %d rectangular polygon zones\n", length(zones_sfc)))

  cat("\n[3/4] Running zonal statistics benchmark...\n")

  warmup <- 2
  runs <- 10

  mask_result <- run_benchmark(
    function() rasterize_polygons_to_mask(zones_sfc, rows, cols),
    runs = runs, warmup = warmup
  )
  mask <- mask_result$result
  mask_hash <- generate_hash(mask)
  cat(sprintf("  ✓ Mask creation: min=%.4fs, mean=%.4fs\n",
              min(mask_result$times), mean(mask_result$times)))

  stats_result <- run_benchmark(
    function() vectorized_zonal_stats(raster_matrix, mask),
    runs = runs, warmup = warmup
  )
  stats <- stats_result$result

  zonal_hash <- generate_hash(stats$means)
  cat(sprintf("  ✓ Zonal stats: min=%.4fs, mean=%.4fs\n",
              min(stats_result$times), mean(stats_result$times)))
  cat(sprintf("  ✓ Validation hash: %s\n", zonal_hash))

  output_data <- list(
    language = "r",
    scenario = "zonal_statistics",
    zone_type = "rectangular_polygons",
    n_zones = n_zones * n_zones,
    results = list(
      mask_creation = list(
        min_time_s = min(mask_result$times),
        mean_time_s = mean(mask_result$times),
        std_time_s = sd(mask_result$times),
        median_time_s = median(mask_result$times),
        max_time_s = max(mask_result$times),
        times = as.list(mask_result$times),
        n_zones = n_zones * n_zones,
        validation_hash = mask_hash
      ),
      zonal_stats = list(
        min_time_s = min(stats_result$times),
        mean_time_s = mean(stats_result$times),
        std_time_s = sd(stats_result$times),
        median_time_s = median(stats_result$times),
        max_time_s = max(stats_result$times),
        times = as.list(stats_result$times),
        n_zones = length(stats$means),
        validation_hash = zonal_hash
      )
    ),
    all_hashes = c(mask_hash, zonal_hash),
    combined_hash = generate_hash(c(mask_hash, zonal_hash))
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

  write_json(output_data, file.path(RESULTS_DIR, "zonal_stats_r.json"),
             pretty = TRUE, auto_unbox = TRUE)
  write_json(output_data, file.path(OUTPUT_DIR, "zonal_stats_r_results.json"),
             pretty = TRUE, auto_unbox = TRUE)

  cat("✓ Results saved\n")
  cat(sprintf("✓ Combined validation hash: %s\n", output_data$combined_hash))

  cat("\n", strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")

  return(output_data)
}

run_zonal_stats_benchmark()
