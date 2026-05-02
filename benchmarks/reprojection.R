#!/usr/bin/env Rscript
# =============================================================================
# SCENARIO G: Coordinate Reprojection - R Implementation
# Tests: EPSG:4326 <-> UTM/Web Mercator reprojection performance
#
# Uses sf/PROJ library (via sf::st_transform) for fair comparison with Python's pyproj.
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

suppressPackageStartupMessages({
  library(sf)
  library(jsonlite)
  library(digest)
})

source(file.path(PROJECT_ROOT, "benchmarks", "common_hash.R"))

PROJ_AVAILABLE <- require(sf)

OUTPUT_DIR <- "validation"
RESULTS_DIR <- "results"

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

  zones <- pmax(pmin(floor((lon + 180) / 6) + 1, 60), 1)
  for (zone in unique(zones)) {
    mask <- zones == zone
    epsg <- ifelse(any(lat[mask] >= 0), paste0("326", zone), paste0("327", zone))

    pts <- data.frame(
      lon = lon[mask],
      lat = lat[mask]
    )
    sf_pts <- st_as_sf(pts, coords = c("lon", "lat"), crs = "EPSG:4326")

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

load_reprojection_data <- function(data_mode) {
  if (data_mode == "synthetic") {
    cat("  Generating synthetic test points (1M, seed 42)...\n")
    return(list(lat = runif(1000000, -90, 90), lon = runif(1000000, -180, 180), source = "synthetic"))
  }
  gps_path <- file.path(PROJECT_ROOT, "data", "gps_points_1m.csv")
  if (file.exists(gps_path) || data_mode == "real") {
    result <- tryCatch({
      cat(sprintf("  Loading GPS points: %s\n", gps_path))
      df <- read.csv(gps_path)
      cat(sprintf("  ✓ Loaded %d real GPS points\n", nrow(df)))
      list(lat = df$lat, lon = df$lon, source = "real")
    }, error = function(e) {
      if (data_mode == "real") {
        cat(sprintf("  x Real data load failed: %s\n", e$message))
        quit(status = 1)
      }
      cat(sprintf("  - Real data unavailable (%s), using synthetic\n", e$message))
      list(lat = NULL, lon = NULL, source = NULL)
    })
    if (!is.null(result$lat)) return(result)
  }
  set.seed(42)
  return(list(lat = runif(1000000, -90, 90), lon = runif(1000000, -180, 180), source = "synthetic"))
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
  args <- commandArgs(trailingOnly = TRUE)
  data_mode <- "auto"
  for (i in seq_along(args)) {
    if (args[i] == "--data" && i < length(args)) {
      data_mode <- args[i + 1]
    }
  }

  cat(strrep("=", 70), "\n")
  cat("R - Scenario G: Coordinate Reprojection\n")
  cat(sprintf("Using sf/PROJ: %s\n", PROJ_AVAILABLE))
  cat(strrep("=", 70), "\n\n")

  # Load data once based on mode
  all_data <- load_reprojection_data(data_mode)

  n_runs <- 10
  n_warmup <- 2
  sizes <- c(1000, 5000, 10000, 50000, 100000, 500000)

  results <- list()
  all_hashes <- character(0)

  cat("[1/2] Web Mercator (EPSG:4326 -> 3857)...\n")

  for (n in sizes) {
    n_subset <- min(n, length(all_data$lat))
    func <- function() reproject_to_web_mercator(all_data$lat[1:n_subset], all_data$lon[1:n_subset])
    bench <- run_benchmark(func, n_runs, n_warmup)

    merc_result <- reproject_to_web_mercator(all_data$lat[1:n_subset], all_data$lon[1:n_subset])
    merc_hash <- generate_hash(c(mean(merc_result$x), mean(merc_result$y)))
    all_hashes <- c(all_hashes, merc_hash)

    key <- paste0("mercator_", n)
    results[[key]] <- list(
      n_points = n,
      min_time_s = min(bench$times),
      mean_time_s = mean(bench$times),
      std_time_s = sd(bench$times),
      median_time_s = median(bench$times),
      max_time_s = max(bench$times),
      times = as.list(bench$times),
      points_per_second = round(n / min(bench$times)),
      validation_hash = merc_hash
    )
    cat(sprintf("  %d points: min=%.4fs, mean=%.4fs, hash=%s\n",
                n, min(bench$times), mean(bench$times), merc_hash))
  }

  cat("\n[2/2] UTM (zone-optimized)...\n")

  for (n in sizes) {
    n_subset <- min(n, length(all_data$lat))
    func <- function() reproject_to_utm_batch(all_data$lat[1:n_subset], all_data$lon[1:n_subset])
    bench <- run_benchmark(func, n_runs, n_warmup)

    utm_result <- reproject_to_utm_batch(all_data$lat[1:n_subset], all_data$lon[1:n_subset])
    utm_hash <- generate_hash(c(mean(utm_result$x), mean(utm_result$y)))
    all_hashes <- c(all_hashes, utm_hash)

    key <- paste0("utm_", n)
    results[[key]] <- list(
      n_points = n,
      min_time_s = min(bench$times),
      mean_time_s = mean(bench$times),
      std_time_s = sd(bench$times),
      median_time_s = median(bench$times),
      max_time_s = max(bench$times),
      times = as.list(bench$times),
      points_per_second = round(n / min(bench$times)),
      validation_hash = utm_hash
    )
    cat(sprintf("  %d points: min=%.4fs, mean=%.4fs, hash=%s\n",
                n, min(bench$times), mean(bench$times), utm_hash))
  }

  output_data <- list(
    language = "r",
    scenario = "coordinate_reprojection",
    data_source = all_data$source,
    data_description = if (all_data$source == "real") "GPS points 1M (subsampled)" else "synthetic points (seed 42)",
    library = ifelse(PROJ_AVAILABLE, "sf/PROJ", "manual"),
    results = results,
    all_hashes = all_hashes,
    combined_hash = generate_hash(all_hashes)
  )

  dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

  json_output <- toJSON(output_data, auto_unbox = TRUE, pretty = TRUE)
  writeLines(json_output, file.path(OUTPUT_DIR, "reprojection_r_results.json"))
  writeLines(json_output, file.path(RESULTS_DIR, "reprojection_r.json"))

  cat("\n✓ Results saved\n")
  cat(sprintf("✓ Combined validation hash: %s\n", output_data$combined_hash))
  cat(strrep("=", 70), "\n")
}

main()
