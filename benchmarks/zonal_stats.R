
#!/usr/bin/env Rscript
# =============================================================================
# SCENARIO F: Zonal Statistics - R Implementation
# Tests: Polygon-based raster statistics (mean, std, sum over zones)
#
# Uses IDENTICAL rectangular polygon zones as Python and Julia for valid comparison.
# =============================================================================

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(jsonlite)
  library(digest)
})

# Get script directory
get_script_dir <- function() {
  cmdArgs <- commandArgs(trailingOnly = FALSE)
  fileArg <- cmdArgs[grep("^--file=", cmdArgs)]
  if (length(fileArg) == 0) {
    return(".")
  }
  filePath <- sub("^--file=", "", fileArg)
  return(dirname(filePath))
}

script_dir <- get_script_dir()
OUTPUT_DIR <- "validation"
RESULTS_DIR <- "results"

source(file.path(script_dir, "common_hash.R"))

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

      # Create polygon using sf
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

rasterize_polygons_to_mask <- function(zones_sfc, rows, cols) {
  mask <- matrix(0, nrow = rows, ncol = cols)
  lat_step <- 180.0 / rows
  lon_step <- 360.0 / cols
  n_zones <- length(zones_sfc)

  for (zone_id in 1:n_zones) {
    geom <- zones_sfc[[zone_id]]
    bbox <- sf::st_bbox(geom)

    r0 <- max(1, floor((90 - bbox["ymax"]) / lat_step) + 1)
    r1 <- min(rows, ceiling((90 - bbox["ymin"]) / lat_step))
    c0 <- max(1, floor((bbox["xmin"] + 180) / lon_step) + 1)
    c1 <- min(cols, ceiling((bbox["xmax"] + 180) / lon_step))

    r0 <- max(1, r0)
    r1 <- min(rows, r1)
    c0 <- max(1, c0)
    c1 <- min(cols, c1)

    for (r in r0:r1) {
      for (c in c0:c1) {
        lat <- 90 - (r - 0.5) * lat_step
        lon <- -180 + (c - 0.5) * lon_step
        pt <- sf::st_point(c(lon, lat))
        if (sf::st_contains(geom, pt, sparse = FALSE) || sf::st_intersects(geom, pt, sparse = FALSE)) {
          mask[r, c] <- zone_id
        }
      }
    }
  }

  mask
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

  set.seed(42)
  raster_vals <- runif(rows * cols) * 3000
  raster_matrix <- matrix(raster_vals, nrow = rows, ncol = cols)

  cat(sprintf("\n[1/4] Created synthetic raster: %d x %d cells\n", rows, cols))

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
  cat(sprintf("  ✓ Mask creation: min=%.4fs, mean=%.4fs\n",
              min(mask_result$times), mean(mask_result$times)))

  stats_result <- run_benchmark(
    function() vectorized_zonal_stats(raster_matrix, mask),
    runs = runs, warmup = warmup
  )
  stats <- stats_result$result

  cat(sprintf("  ✓ Zonal stats: min=%.4fs, mean=%.4fs\n",
              min(stats_result$times), mean(stats_result$times)))

  zonal_hash <- generate_hash(stats$means)
  cat(sprintf("  ✓ Validation hash: %s\n", zonal_hash))

  output_data <- list(
    language = "r",
    scenario = "zonal_stats",
    zone_type = "rectangular_polygons",
    n_zones = n_zones * n_zones,
    min_time_s = min(stats_result$times),
    mean_time_s = mean(stats_result$times),
    std_time_s = sd(stats_result$times),
    polygons = length(zones_sfc),
    hash = zonal_hash,
    warmup = warmup,
    runs = runs
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

  write_json(output_data, file.path(RESULTS_DIR, "zonal_stats_r.json"),
             pretty = TRUE, auto_unbox = TRUE)
  write_json(output_data, file.path(OUTPUT_DIR, "zonal_stats_r_results.json"),
             pretty = TRUE, auto_unbox = TRUE)

  cat("✓ Results saved\n")
  cat(sprintf("✓ Hash: %s\n", zonal_hash))

  cat("\n", strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")

  return(output_data)
}

run_zonal_stats_benchmark()
