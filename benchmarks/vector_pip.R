#!/usr/bin/env Rscript
################################################################################
# SCENARIO B: Complex Vector Operations – R Implementation (terra only)
################################################################################
# Task: Point-in-Polygon spatial join + Haversine distance calculation
# Uses terra::intersect for spatial indexing (similar to Python/Julia spatial index)
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
  library(jsonlite)
  library(digest)
})

RUNS <- 10
WARMUP <- 2

haversine_vectorized <- function(lat1, lon1, lat2, lon2) {
  R <- 6371000.0
  lat1_rad <- lat1 * pi / 180
  lat2_rad <- lat2 * pi / 180
  dlat <- (lat2 - lat1) * pi / 180
  dlon <- (lon2 - lon1) * pi / 180
  a <- sin(dlat / 2)^2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  R * c
}

run_pip_and_distances <- function(points, polys) {
  # Use terra::intersect which uses internal spatial indexing
  matches <- intersect(points, polys)
  n_matched <- nrow(matches)

  if (n_matched == 0) {
    return(list(
      n_matched = 0,
      total_distance = 0.0,
      mean_distance = 0.0,
      median_distance = 0.0,
      max_distance = 0.0,
      distances = numeric(0)
    ))
  }

  # Get matched coordinates
  matched_coords <- crds(points)[matches@data[[1]], ]
  matched_centroids <- crds(centroids(polys))[matches@data[[2]], ]
  
  point_lats <- matched_coords[, "y"]
  point_lons <- matched_coords[, "x"]
  centroid_lats <- matched_centroids[, "y"]
  centroid_lons <- matched_centroids[, "x"]
  
  distances <- haversine_vectorized(point_lats, point_lons, centroid_lats, centroid_lons)

  list(
    n_matched = n_matched,
    total_distance = sum(distances),
    mean_distance = mean(distances),
    median_distance = median(distances),
    max_distance = max(distances),
    distances = distances
  )
}

generate_synthetic_polygons <- function(n_polys = 50) {
  set.seed(42)
  lat_step <- 180.0 / (n_polys %/% 2 + 1)
  lon_step <- 360.0 / (n_polys %/% 2 + 1)
  pts_list <- list()
  idx <- 1
  for (i in 0:(n_polys %/% 2)) {
    for (j in 0:(n_polys %/% 2)) {
      if (idx > n_polys) break
      min_lon <- -180 + j * lon_step + runif(1, -2, 2)
      max_lon <- min_lon + lon_step + runif(1, -2, 2)
      min_lat <- -90 + i * lat_step + runif(1, -2, 2)
      max_lat <- min_lat + lat_step + runif(1, -2, 2)
      min_lon <- max(-180, min(min_lon, 180))
      max_lon <- max(-180, min(max_lon, 180))
      min_lat <- max(-90, min(min_lat, 90))
      max_lat <- max(-90, min(max_lat, 90))
      if (max_lon > min_lon && max_lat > min_lat) {
        poly <- vect(rbind(c(min_lon, min_lat), c(max_lon, min_lat),
                          c(max_lon, max_lat), c(min_lon, max_lat), c(min_lon, min_lat)),
                    type = "polygons", crs = "EPSG:4326")
        poly$name <- paste0("Country_", idx)
        pts_list[[idx]] <- poly
        idx <- idx + 1
      }
    }
  }
  do.call(rbind, pts_list)
}

generate_synthetic_points <- function(n = 1000000) {
  set.seed(42)
  data.frame(lon = runif(n, -180, 180), lat = runif(n, -90, 90))
}

load_vector_data <- function(data_mode) {
  if (data_mode == "synthetic") {
    cat("  Generating synthetic polygons and points...\n")
    polys <- generate_synthetic_polygons()
    points_df <- generate_synthetic_points()
    return(list(polys = polys, points_df = points_df, source = "synthetic"))
  }
  poly_path <- file.path(DATA_DIR, "natural_earth_countries.gpkg")
  points_path <- file.path(DATA_DIR, "gps_points_1m.csv")
  poly_exists <- file.exists(poly_path)
  points_exists <- file.exists(points_path)
  if ((poly_exists && points_exists) || data_mode == "real") {
    result <- tryCatch({
      if (!poly_exists && data_mode == "real") {
        cat(sprintf("  x Real polygon data not found: %s\n", poly_path))
        quit(status = 1)
      }
      if (!points_exists && data_mode == "real") {
        cat(sprintf("  x Real GPS data not found: %s\n", points_path))
        quit(status = 1)
      }
      if (poly_exists && points_exists) {
        cat("  Loading real Natural Earth polygons + GPS points...\n")
        polys <- vect(poly_path)
        points_df <- read.csv(points_path)
        list(polys = polys, points_df = points_df, source = "real")
      } else {
        list(polys = NULL, points_df = NULL, source = NULL)
      }
    }, error = function(e) {
      if (data_mode == "real") {
        cat(sprintf("  x Real data load failed: %s\n", e$message))
        quit(status = 1)
      }
      cat(sprintf("  - Real data unavailable (%s), using synthetic\n", e$message))
      list(polys = NULL, points_df = NULL, source = NULL)
    })
    if (!is.null(result$polys)) return(result)
  }
  cat("  → Using synthetic data\n")
  polys <- generate_synthetic_polygons()
  points_df <- generate_synthetic_points()
  return(list(polys = polys, points_df = points_df, source = "synthetic"))
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
  cat("R (terra) - Scenario B: Vector Point-in-Polygon + Haversine\n")
  cat(strrep("=", 70), "\n")

  cat("\n[1/4] Loading data...\n")
  vec_data <- load_vector_data(data_mode)
  polys <- vec_data$polys
  points_df <- vec_data$points_df
  data_source <- vec_data$source
  points <- vect(points_df, geom = c("lon", "lat"), crs = "EPSG:4326")
  cat(sprintf("  ✓ Loaded %d polygons and %d points (%s)\n", nrow(polys), nrow(points), data_source))

  cat(sprintf("\n[2/4] Running spatial join + Haversine (%d runs, %d warmup)...\n", RUNS, WARMUP))

  task <- function() {
    run_pip_and_distances(points, polys)
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
  cat(sprintf("  ✓ Matched %d points to polygons\n", result$n_matched))

  cat("\n[3/4] Distance statistics...\n")
  cat(sprintf("  ✓ Total distance: %s meters\n", format(result$total_distance, big.mark = ",")))
  cat(sprintf("  ✓ Mean distance: %s meters\n", format(result$mean_distance, big.mark = ",")))
  cat(sprintf("  ✓ Median distance: %s meters\n", format(result$median_distance, big.mark = ",")))
  cat(sprintf("  ✓ Max distance: %s meters\n", format(result$max_distance, big.mark = ",")))

  cat("\n[4/4] Validation and export...\n")
  result_hash <- generate_hash(result$distances)
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))

  results <- list(
    language = "r",
    scenario = "vector_pip",
    data_source = data_source,
    data_description = if (data_source == "real") "Natural Earth + GPS 1M" else "synthetic polygons + 1M points (seed 42)",
    n_points = nrow(points),
    n_polygons = nrow(polys),
    matches_found = result$n_matched,
    total_distance_m = result$total_distance,
    mean_distance_m = result$mean_distance,
    median_distance_m = result$median_distance,
    max_distance_m = result$max_distance,
    min_time_s = min(times),
    mean_time_s = mean(times),
    std_time_s = sd(times),
    max_time_s = max(times),
    times = times,
    validation_hash = result_hash
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(VALIDATION_DIR, showWarnings = FALSE, recursive = TRUE)

  write_json(results, file.path(OUTPUT_DIR, "vector_pip_r.json"), pretty = TRUE, auto_unbox = TRUE)
  write_json(results, file.path(VALIDATION_DIR, "vector_r_results.json"), pretty = TRUE, auto_unbox = TRUE)

  cat("✓ Results saved\n")
  cat(strrep("=", 70), "\n")
  cat("Note: Minimum times are primary metrics (Chen & Revels 2016)\n")
  cat(strrep("=", 70), "\n")

  return(0)
}

quit(status = main())
