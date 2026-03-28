#!/usr/bin/env Rscript
################################################################################
# SCENARIO B: Complex Vector Operations – R Implementation (terra only)
################################################################################
# Task: Point-in-Polygon spatial join + Haversine distance calculation
# Uses terra for vector operations (no sf dependency)
################################################################################

suppressPackageStartupMessages({
  library(terra)
  library(jsonlite)
  library(digest)
})

#' Vectorized Haversine distance calculation
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

  # ===========================================================================
  # 1. Data Loading
  # ===========================================================================
  cat("\n[1/4] Loading data...\n")

  # Load polygon dataset (Natural Earth countries) as SpatVector
  polys <- vect("data/natural_earth_countries.gpkg")
  cat(sprintf("  ✓ Loaded %d polygons\n", nrow(polys)))

  # Load point dataset
  points_df <- read.csv("data/gps_points_1m.csv")
  points <- vect(points_df, geom = c("lon", "lat"), crs = "EPSG:4326")
  cat(sprintf("  ✓ Loaded %d points\n", nrow(points)))

  # ===========================================================================
  # 2. Spatial Join (Point-in-Polygon) using terra::relate
  # ===========================================================================
  cat("\n[2/4] Performing spatial join...\n")

  n_points <- nrow(points)
  n_polys <- nrow(polys)
  
  # Use relate with batches by polygon to avoid memory issues
  # Each batch processes relate on a subset of polygons
  matched_points <- integer(0)
  matched_polys <- integer(0)
  
  batch_size <- 500  # Process 500 polygons at a time
  for (poly_start in seq(1, n_polys, by = batch_size)) {
    poly_end <- min(poly_start + batch_size - 1, n_polys)
    poly_batch <- polys[poly_start:poly_end]
    
    # Relate points to this batch of polygons
    rel_mat <- relate(points, poly_batch, "intersects")
    
    # Find matching points
    point_matches <- rowSums(rel_mat) > 0
    poly_indices <- max.col(rel_mat) * point_matches
    poly_indices[poly_indices == 0] <- NA
    poly_indices[!point_matches] <- NA
    
    # Add to results
    matched_points <- c(matched_points, which(point_matches))
    matched_polys <- c(matched_polys, poly_indices[point_matches] + poly_start - 1)
    
    if (poly_start %% 500 == 0) {
      cat(sprintf("    Processed %d/%d polygons (%d matches found)...\n", 
                  poly_end, n_polys, length(matched_points)))
    }
  }
  
  # Remove duplicates (if a point matches multiple polygons, keep first)
  unique_idx <- !duplicated(matched_points)
  matched_points <- matched_points[unique_idx]
  matched_polys <- matched_polys[unique_idx]
  
  n_matched <- length(matched_points)
  cat(sprintf("  ✓ Matched %d points to polygons\n", n_matched))
  cat(sprintf("  ✓ Match rate: %.2f%%\n", 100 * n_matched / n_points))

  # ===========================================================================
  # 3. Distance Calculation
  # ===========================================================================
  cat("\n[3/4] Calculating Haversine distances...\n")

  if (n_matched == 0) {
    cat("  ⚠ No points matched any polygons!\n")
    distances <- numeric(0)
  } else {
    # Extract point coordinates
    point_coords <- crds(points)[matched_points, ]
    point_lats <- point_coords[, "y"]
    point_lons <- point_coords[, "x"]

    # Compute centroids of matched polygons
    poly_centroids <- centroids(polys[matched_polys])
    centroid_coords <- crds(poly_centroids)
    centroid_lats <- centroid_coords[, "y"]
    centroid_lons <- centroid_coords[, "x"]

    # Vectorized Haversine
    distances <- haversine_vectorized(
      point_lats, point_lons,
      centroid_lats, centroid_lons
    )
  }

  # ===========================================================================
  # 4. Results & Validation
  # ===========================================================================
  cat("\n[4/4] Computing metrics...\n")

  total_distance <- sum(distances)
  mean_distance <- mean(distances)
  median_distance <- median(distances)
  max_distance <- max(distances)

  cat(sprintf("  ✓ Total distance: %s meters\n", format(total_distance, big.mark = ",")))
  cat(sprintf("  ✓ Mean distance: %s meters\n", format(mean_distance, big.mark = ",")))
  cat(sprintf("  ✓ Median distance: %s meters\n", format(median_distance, big.mark = ",")))
  cat(sprintf("  ✓ Max distance: %s meters\n", format(max_distance, big.mark = ",")))

  # Generate validation hash
  result_str <- sprintf("%.6f_%d_%.6f", total_distance, n_matched, mean_distance)
  result_hash <- substr(digest(result_str, algo = "sha256"), 1, 16)

  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))

  # Export results
  results <- list(
    language = "r",
    scenario = "vector_pip",
    points_processed = nrow(points),
    matches_found = n_matched,
    total_distance_m = total_distance,
    mean_distance_m = mean_distance,
    median_distance_m = median_distance,
    max_distance_m = max_distance,
    validation_hash = result_hash
  )

  dir.create("validation", showWarnings = FALSE)
  write_json(
    results,
    "validation/vector_r_results.json",
    pretty = TRUE,
    auto_unbox = TRUE
  )

  cat("\n  ✓ Results saved to validation/vector_r_results.json\n")
  cat(strrep("=", 70), "\n")

  return(0)
}

quit(status = main())
