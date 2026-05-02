#!/usr/bin/env Rscript
#===============================================================================
# I/O Operations Benchmark - R Implementation
#===============================================================================
# Tests file I/O performance for CSV and binary formats
# Tasks: CSV Write/Read, Binary Write/Read
#===============================================================================

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

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

benchmark_csv_write <- function(n_rows) {
  dt <- data.table(
    lat = runif(n_rows, -90, 90),
    lon = runif(n_rows, -180, 180),
    device_id = sample(10000, n_rows, replace = TRUE)
  )
  output_path <- file.path(DATA_DIR, "io_test_r.csv")

  start_time <- Sys.time()
  fwrite(dt, output_path)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  file_size <- file.info(output_path)$size
  return(list(elapsed = elapsed, file_size = file_size))
}

benchmark_csv_read <- function() {
  input_path <- file.path(DATA_DIR, "io_test_r.csv")

  start_time <- Sys.time()
  dt <- fread(input_path)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  return(list(elapsed = elapsed, n_rows = nrow(dt)))
}

benchmark_binary_write <- function(n_values) {
  arr <- rnorm(n_values)
  output_path <- file.path(DATA_DIR, "io_test_r.bin")

  start_time <- Sys.time()
  con <- file(output_path, "wb")
  writeBin(as.double(arr), con)
  close(con)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  file_size <- file.info(output_path)$size
  return(list(elapsed = elapsed, file_size = file_size))
}

benchmark_binary_read <- function() {
  input_path <- file.path(DATA_DIR, "io_test_r.bin")

  start_time <- Sys.time()
  con <- file(input_path, "rb")
  arr <- readBin(con, "double", n = 1e6, size = 8)
  close(con)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  return(list(elapsed = elapsed, n_values = length(arr)))
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  data_mode <- "auto"
  size_mode <- "small"
  for (i in seq_along(args)) {
    if (args[i] == "--data" && i < length(args)) {
      data_mode <- args[i + 1]
    } else if (args[i] == "--size" && i < length(args)) {
      size_mode <- args[i + 1]
    }
  }

  data_source <- "synthetic"
  data_description <- "random CSV/binary data (seed 42)"

  size_map <- c(small = 1000000, large = 10000000)
  n_csv_rows <- size_map[size_mode]
  n_binary_values <- size_map[size_mode]
  n_runs <- 30
  n_warmup <- 5

  set.seed(42)

  cat(strrep("=", 70), "\n")
  cat(sprintf("R - I/O Operations Benchmark (%s size)\n", size_mode))
  cat(strrep("=", 70), "\n")

  dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)
  dir.create("results", showWarnings = FALSE, recursive = TRUE)

  results <- list()

  # Task 1: CSV Write
  cat(sprintf("\n[1/4] CSV Write (%s rows)...\n", format(n_csv_rows, big.mark = ",")))
  for (i in 1:n_warmup) benchmark_csv_write(n_csv_rows)
  times <- numeric(n_runs)
  file_size <- 0
  for (i in 1:n_runs) {
    res <- benchmark_csv_write(n_csv_rows)
    times[i] <- res$elapsed
    file_size <- res$file_size
  }
  results$csv_write <- list(
    mean = mean(times), std = sd(times),
    min = min(times), max = max(times), median = median(times),
    file_size_mb = file_size / (1024^2), times = as.list(times)
  )
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", results$csv_write$min))

  # Task 2: CSV Read
  cat(sprintf("\n[2/4] CSV Read (%s rows)...\n", format(n_csv_rows, big.mark = ",")))
  for (i in 1:n_warmup) benchmark_csv_read()
  times <- numeric(n_runs)
  for (i in 1:n_runs) {
    res <- benchmark_csv_read()
    times[i] <- res$elapsed
  }
  results$csv_read <- list(
    mean = mean(times), std = sd(times),
    min = min(times), max = max(times), median = median(times),
    rows_read = n_csv_rows, times = as.list(times)
  )
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", results$csv_read$min))

  # Task 3: Binary Write
  cat(sprintf("\n[3/4] Binary Write (%s float64 values)...\n", format(n_binary_values, big.mark = ",")))
  for (i in 1:n_warmup) benchmark_binary_write(n_binary_values)
  times <- numeric(n_runs)
  file_size <- 0
  for (i in 1:n_runs) {
    res <- benchmark_binary_write(n_binary_values)
    times[i] <- res$elapsed
    file_size <- res$file_size
  }
  results$binary_write <- list(
    mean = mean(times), std = sd(times),
    min = min(times), max = max(times), median = median(times),
    file_size_mb = file_size / (1024^2), times = as.list(times)
  )
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", results$binary_write$min))

  # Task 4: Binary Read
  cat(sprintf("\n[4/4] Binary Read (%s float64 values)...\n", format(n_binary_values, big.mark = ",")))
  for (i in 1:n_warmup) benchmark_binary_read()
  times <- numeric(n_runs)
  for (i in 1:n_runs) {
    res <- benchmark_binary_read()
    times[i] <- res$elapsed
  }
  results$binary_read <- list(
    mean = mean(times), std = sd(times),
    min = min(times), max = max(times), median = median(times),
    values_read = n_binary_values, times = as.list(times)
  )
  cat(sprintf("  ✓ Min: %.4fs (primary)\n", results$binary_read$min))

  # Save results
  cat("\n", strrep("=", 70), "\n")
  cat("SAVING RESULTS...\n")
  cat(strrep("=", 70), "\n")

  output <- list(
    language = "R",
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    n_csv_rows = n_csv_rows,
    n_binary_values = n_binary_values,
    n_runs = n_runs,
    n_warmup = n_warmup,
    data_source = data_source,
    data_description = data_description,
    methodology = "Minimum time as primary estimator (Chen & Revels 2016)",
    results = results
  )

  write_json(output, "results/io_ops_r.json", auto_unbox = TRUE, pretty = TRUE)

  cat("✓ Results saved to: results/io_ops_r.json\n")

  cat("\nCleaning up test files...\n")
  for (path in c(file.path(DATA_DIR, "io_test_r.csv"), file.path(DATA_DIR, "io_test_r.bin"))) {
    if (file.exists(path)) file.remove(path)
  }
  cat("✓ Cleanup complete\n")

  cat("\nNote: Minimum times are primary metrics (Chen & Revels 2016)\n")
}

main()
