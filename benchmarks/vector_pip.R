#!/usr/bin/env Rscript
################################################################################
# SCENARIO B: Vector Point-in-Polygon + Haversine – R (terra only)
################################################################################

suppressPackageStartupMessages({
  library(terra)
  library(jsonlite)
  library(digest)
})

haversine_vectorized <- function(lat1, lon1, lat2, lon2) {
  R <- 6371000.0
  lat1_rad <- lat1 * pi / 180
  lat2_rad <- lat2 * pi / 180
  dlat <- (lat2 - lat1) * pi / 180
  dlon <- (lon2 - lon1) * pi / 180
  a <- sin(dlat / 2)^2 +
       cos(lat1_rad) * cos(lat2_rad) *
       sin(dlon / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  R * c
}

main <- function() {
  cat(strrep("=", 70), "\n")
  cat("R (terra) - Scenario B: Vector Point-in-Polygon + Haversine\n")
  cat(strrep("=", 70), "\n")

  # ---------------------------------------------------------------------------
  # 1. Data Loading
  # ---------------------------------------------------------------------------
  cat("\n[1/4] Loading data...\n")
  polys <- vect("data/natural_earth_countries.gpkg")
  cat(sprintf("  ✓ Loaded %d polygons\n", nrow(polys)))
  points_df <- read.csv("data/gps_points_1m.csv")
  points <- vect(points_df, geom = c("lon", "lat"), crs = "EPSG:4326")
  cat(sprintf("  ✓ Loaded %d points\n", nrow(points)))

  # ---------------------------------------------------------------------------
  # 2. Spatial Join using terra::extract
  # ---------------------------------------------------------------------------
  cat("\n[2/4] Performing spatial join...\n")
  extracted <- extract(polys, points)
  matched <- extracted[!is.na(extracted[,2]), , drop = FALSE]
  matched_poly_ids <- matched[,1]
  matched_point_indices <- as.integer(rownames(matched))
  cat(sprintf("  ✓ Matched %d points to polygons\n", nrow(matched)))
  cat(sprintf("  ✓ Match rate: %.2f%%\n", 100 * nrow(matched) / nrow(points)))

  # ---------------------------------------------------------------------------
  # 3. Distance Calculation
  # ---------------------------------------------------------------------------
  cat("\n[3/4] Calculating Haversine distances...\n")
  point_coords <- crds(points)[matched_point_indices, ]
  point_lats <- point_coords[, "y"]
  point_lons <- point_coords[, "x"]
  poly_centroids <- centroids(polys[matched_poly_ids])
  centroid_coords <- crds(poly_centroids)
  centroid_lats <- centroid_coords[, "y"]
  centroid_lons <- centroid_coords[, "x"]
  distances <- haversine_vectorized(
    point_lats, point_lons,
    centroid_lats, centroid_lons
  )

  # ---------------------------------------------------------------------------
  # 4. Results & Validation
  # ---------------------------------------------------------------------------
  cat("\n[4/4] Computing metrics...\n")
  total_distance <- sum(distances)
  mean_distance <- mean(distances)
  median_distance <- median(distances)
  max_distance <- max(distances)
  cat(sprintf("  ✓ Total distance: %s meters\n", format(total_distance, big.mark = ",")))
  cat(sprintf("  ✓ Mean distance: %s meters\n", format(mean_distance, big.mark = ",")))
  cat(sprintf("  ✓ Median distance: %s meters\n", format(median_distance, big.mark = ",")))
  cat(sprintf("  ✓ Max distance: %s meters\n", format(max_distance, big.mark = ",")))

  result_str <- sprintf("%.6f_%d_%.6f", total_distance, nrow(matched), mean_distance)
  result_hash <- substr(digest(result_str, algo = "sha256"), 1, 16)
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))

  results <- list(
    language = "r",
    scenario = "vector_pip",
    points_processed = nrow(points),
    matches_found = nrow(matched),
    total_distance_m = total_distance,
    mean_distance_m = mean_distance,
    median_distance_m = median_distance,
    max_distance_m = max_distance,
    validation_hash = result_hash
  )

  dir.create("validation", showWarnings = FALSE)
  write_json(results, "validation/vector_r_results.json", pretty = TRUE, auto_unbox = TRUE)
  cat("\n  ✓ Results saved to validation/vector_r_results.json\n")
  cat(strrep("=", 70), "\n")
  return(0)
}

quit(status = main())
