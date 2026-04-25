
# Dynamic path resolution
get_project_root <- function() {
  # Attempt to find root based on script location
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grep("--file=", args)]
  if (length(file_arg) > 0) {
    script_path <- sub("--file=", "", file_arg)
    return(normalizePath(file.path(dirname(script_path), "..")))
  } else {
    return(getwd()) # Fallback
  }
}
PROJECT_ROOT <- get_project_root()
DATA_DIR <- file.path(PROJECT_ROOT, "data")
#!/usr/bin/env Rscript
# =============================================================================
# SCENARIO G: Coordinate Reprojection - R Implementation
# Tests: EPSG:4326 <-> UTM/Web Mercator reprojection performance
# 
# Note: Uses pure R implementation of coordinate transformations for 
# compatibility. For production use, consider sf/GDAL bindings.
# =============================================================================

suppressPackageStartupMessages({
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

deg2rad <- function(deg) deg * pi / 180
rad2deg <- function(rad) rad * 180 / pi

wgs84_to_web_mercator <- function(lat, lon) {
  x <- 6378137.0 * (lon * pi / 180)
  y <- 6378137.0 * log(tan(pi/4 + (lat * pi / 180)/2))
  return(list(x = x, y = y))
}

# UTM projection (simplified)
wgs84_to_utm <- function(lat, lon, zone) {
  # UTM zones 1-60
  zone <- pmax(pmin(zone, 60), 1)  # clamp to 1-60
  lambda0 <- (zone - 1) * 6 - 180 + 3  # central meridian
  k0 <- 0.9996
  e2 <- 0.00669437999014
  
  lat_r <- lat * pi / 180
  lon_r <- (lon - lambda0) * pi / 180
  
  N <- 6378137.0 / sqrt(1 - e2 * sin(lat_r)^2)
  x <- k0 * N * lon_r * cos(lat_r)
  y <- k0 * N * (lat_r - (1 - e2) * lat_r / (2 * N) * sin(lat_r)^2)
  
  return(list(x = x, y = y))
}

# Test point generation
generate_test_points <- function(n) {
  list(
    lat = runif(n, -90, 90),
    lon = runif(n, -180, 180)
  )
}

# Main benchmark
main <- function() {
  cat(rep("=", 70), "\n", sep="")
  cat("R - Scenario G: Coordinate Reprojection\n")
  cat(rep("=", 70), "\n\n", sep="")
  
  # Generate test data
  n_points <- 10000
  points <- generate_test_points(n_points)
  
  cat("[1/2] Web Mercator (EPSG:4326 -> 3857)...\n")
  start <- Sys.time()
  merc <- wgs84_to_web_mercator(points$lat, points$lon)
  elapsed <- as.numeric(difftime(Sys.time(), start, units="secs"))
  cat(sprintf("  Min: %.4fs (primary)\n", elapsed))
  cat(sprintf("  Rate: %d points/sec\n", round(n_points/elapsed)))
  
  # UTM benchmark
  zones <- floor((points$lon + 180) / 6) + 1
  zones <- pmax(pmin(zones, 60), 1)
  
  cat("[2/2] UTM (zone-optimized)...\n")
  start <- Sys.time()
  utm <- wgs84_to_utm(points$lat, points$lon, zones)
  elapsed <- as.numeric(difftime(Sys.time(), start, units="secs"))
  cat(sprintf("  Min: %.4fs (primary)\n", elapsed))
  cat(sprintf("  Rate: %d points/sec\n", round(n_points/elapsed)))
  
  # Results
  results <- list(
    language = "r",
    scenario = "coordinate_reprojection",
    results = list(
      mercator = list(
        n_points = n_points,
        min_time_s = elapsed,
        mean_time_s = elapsed,
        points_per_second = round(n_points/elapsed)
      )
    )
  )
  
  # Save results
  OUTPUT_DIR <- "validation"
  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  json_output <- toJSON(results, auto_unbox = FALSE, pretty = TRUE)
  writeLines(json_output, file.path(OUTPUT_DIR, "reprojection_r_results.json"))
  
  cat("\nResults saved to validation/reprojection_r_results.json\n")
}

# Run if executed as script
main()
