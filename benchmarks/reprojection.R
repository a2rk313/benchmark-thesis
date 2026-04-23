
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
