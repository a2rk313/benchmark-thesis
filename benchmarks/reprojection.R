
#!/usr/bin/env Rscript
# =============================================================================
# SCENARIO G: Coordinate Reprojection - R Implementation
# Tests: EPSG:4326 <-> UTM/Web Mercator reprojection performance
# 
# Uses sf/PROJ library (via sf::st_transform) for fair comparison with Python's pyproj.
# =============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(jsonlite)
  library(digest)
})

PROJ_AVAILABLE <- require(sf)

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

reproject_to_web_mercator <- function(lat, lon) {
  if (PROJ_AVAILABLE) {
    pts <- data.frame(
      lon = lon,
      lat = lat
    )
    sf_pts <- st_as_sf(pts, coords = c("lon", "lat"), crs = "EPSG:4326")
    sf_3857 <- st_transform(sf_pts, "EPSG:3857")
    coords <- st_coordinates(sf_3857)
    return(list(
      x = coords[, 1],
      y = coords[, 2]
    ))
  } else {
    return(wgs84_to_web_mercator_manual(lat, lon))
  }
}

reproject_to_utm_batch <- function(lat, lon) {
  if (!PROJ_AVAILABLE) {
    zones <- floor((lon + 180) / 6) + 1
    zones <- pmax(pmin(zones, 60), 1)
    return(wgs84_to_utm_manual(lat, lon, zones))
  }

  n <- length(lat)
  x <- numeric(n)
  y <- numeric(n)
  zones <- integer(n)

  # Group by UTM zone
  for (zone in unique(zones <- pmax(pmin(floor((lon + 180) / 6) + 1), 60), 1))) {
    mask <- zones == zone
    epsg <- ifelse(any(lat[mask] >= 0), paste0("326", zone), paste0("327", zone))

    pts <- data.frame(
      lon = lon[mask],
      lat = lat[mask]
    )
    sf_pts <- st_as_sf(pts, coords = c("lon", "lat"), crs = "EPSG:4326")

    # Try to transform, fall back to manual on failure
    tryCatch({
      sf_utm <- st_transform(sf_pts, epsg)
      coords <- st_coordinates(sf_utm)
      x[mask] <- coords[, 1]
      y[mask] <- coords[, 2]
    }, error = function(e) {
      manual <- wgs84_to_utm_manual(lat[mask], lon[mask], rep(zone, sum(mask)))
      x[mask] <<- manual$x
      y[mask] <<- manual$y
    })
  }

  zones <- pmax(pmin(floor((lon + 180) / 6) + 1, 60), 1)
  return(list(x = x, y = y, zones = zones))
}

wgs84_to_web_mercator_manual <- function(lat, lon) {
  x <- 6378137.0 * (lon * pi / 180)
  y <- 6378137.0 * log(tan(pi/4 + (lat * pi / 180)/2))
  return(list(x = x, y = y))
}

wgs84_to_utm_manual <- function(lat, lon, zones) {
  a <- 6378137.0
  f <- 1.0 / 298.257223563
  k0 <- 0.9996
  e2 <- 2*f - f^2

  n <- length(lat)
  x <- numeric(n)
  y <- numeric(n)

  for (i in 1:n) {
    zone <- max(1, min(60, zones[i]))
    lambda0 <- (zone - 1) * 6 - 180 + 3

    lat_r <- lat[i] * pi / 180
    lon_r <- (lon[i] - lambda0) * pi / 180

    N <- a / sqrt(1 - e2 * sin(lat_r)^2)
    x[i] <- k0 * N * lon_r * cos(lat_r)
    y[i] <- k0 * N * (lat_r - (1 - e2) * lat_r / (2 * N) * sin(lat_r)^2)

    x[i] <- x[i] + 500000.0
    if (lat[i] < 0) {
      y[i] <- y[i] + 10000000.0
    }
  }

  return(list(x = x, y = y))
}

generate_test_points <- function(n) {
  set.seed(42)
  list(
    lat = runif(n, -90, 90),
    lon = runif(n, -180, 180)
  )
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

main <- function() {
  cat(rep("=", 70), "\n", sep="")
  cat("R - Scenario G: Coordinate Reprojection\n")
  cat(sprintf("Using sf/PROJ: %s\n", PROJ_AVAILABLE))
  cat(rep("=", 70), "\n\n", sep="")

  n_runs <- 5
  n_warmup <- 2
  sizes <- c(1000, 5000, 10000)

  points <- generate_test_points(10000)

  cat("[1/2] Web Mercator (EPSG:4326 -> 3857)...\n")

  merc_results <- list()
  for (n in sizes) {
    func <- function() reproject_to_web_mercator(points$lat[1:n], points$lon[1:n])
    bench <- run_benchmark(func, n_runs, n_warmup)

    key <- paste0("mercator_", n)
    merc_results[[key]] <- list(
      n_points = n,
      min_time_s = min(bench$times),
      mean_time_s = mean(bench$times),
      std_time_s = sd(bench$times),
      points_per_second = round(n / min(bench$times))
    )
    cat(sprintf("  %d points: min=%.4fs, mean=%.4fs\n", n, min(bench$times), mean(bench$times)))
  }

  cat("[2/2] UTM (zone-optimized)...\n")

  utm_results <- list()
  for (n in sizes) {
    func <- function() reproject_to_utm_batch(points$lat[1:n], points$lon[1:n])
    bench <- run_benchmark(func, n_runs, n_warmup)

    key <- paste0("utm_", n)
    utm_results[[key]] <- list(
      n_points = n,
      min_time_s = min(bench$times),
      mean_time_s = mean(bench$times),
      std_time_s = sd(bench$times),
      points_per_second = round(n / min(bench$times))
    )
    cat(sprintf("  %d points: min=%.4fs, mean=%.4fs\n", n, min(bench$times), mean(bench$times)))
  }

  results <- list(
    language = "r",
    scenario = "coordinate_reprojection",
    library = ifelse(PROJ_AVAILABLE, "sf/PROJ", "manual"),
    results = c(merc_results, utm_results)
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

  json_output <- toJSON(results, auto_unbox = FALSE, pretty = TRUE)
  writeLines(json_output, file.path(RESULTS_DIR, "reprojection_r.json"))
  writeLines(json_output, file.path(OUTPUT_DIR, "reprojection_r_results.json"))

  cat("\nResults saved to results/reprojection_r.json\n")
}

main()
