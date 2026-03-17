#!/usr/bin/env Rscript
# ==============================================================================
# I/O Operations Benchmark - R Implementation
# ==============================================================================
# Benchmark tasks: CSV write/read, Binary write/read, Random access
# Using data.table for optimized I/O performance
# Following Chen & Revels (2016) methodology: minimum as primary estimator
# ==============================================================================

library(data.table)
library(jsonlite)

benchmark_csv_write <- function(n_rows = 1000000) {
  # Pre-generate data (not timed)
  dt <- data.table(
    id = 1:n_rows,
    value = rnorm(n_rows),
    category = sample(c("A", "B", "C", "D"), n_rows, replace = TRUE),
    timestamp = sample(1:1000000, n_rows, replace = TRUE)
  )
  
  # Timed operation
  start_time <- proc.time()["elapsed"]
  fwrite(dt, "data/benchmark_output.csv")
  elapsed <- proc.time()["elapsed"] - start_time
  
  return(elapsed)
}

benchmark_csv_read <- function() {
  # Timed operation
  start_time <- proc.time()["elapsed"]
  dt <- fread("data/benchmark_output.csv")
  elapsed <- proc.time()["elapsed"] - start_time
  
  return(elapsed)
}

benchmark_binary_write <- function(n_elements = 10000000) {
  # Pre-generate data (not timed)
  data <- rnorm(n_elements)
  
  # Timed operation
  start_time <- proc.time()["elapsed"]
  con <- file("data/benchmark_binary.bin", "wb")
  writeBin(data, con)
  close(con)
  elapsed <- proc.time()["elapsed"] - start_time
  
  return(elapsed)
}

benchmark_binary_read <- function() {
  # Timed operation
  start_time <- proc.time()["elapsed"]
  con <- file("data/benchmark_binary.bin", "rb")
  data <- readBin(con, "numeric", n = 10000000)
  close(con)
  elapsed <- proc.time()["elapsed"] - start_time
  
  return(elapsed)
}

benchmark_random_access <- function(n_reads = 10000) {
  # Create test file if needed
  if (!file.exists("data/benchmark_binary.bin")) {
    data <- rnorm(10000000)
    con <- file("data/benchmark_binary.bin", "wb")
    writeBin(data, con)
    close(con)
  }
  
  # Generate random positions (not timed)
  set.seed(42)
  positions <- sample(1:9999999, n_reads) * 8  # 8 bytes per double
  
  # Timed operation
  start_time <- proc.time()["elapsed"]
  results <- numeric(n_reads)
  con <- file("data/benchmark_binary.bin", "rb")
  for (i in 1:n_reads) {
    seek(con, where = positions[i], origin = "start")
    results[i] <- readBin(con, "numeric", n = 1)
  }
  close(con)
  elapsed <- proc.time()["elapsed"] - start_time
  
  return(elapsed)
}

main <- function() {
  cat(strrep("=", 70), "\n")
  cat("R - I/O Operations Benchmark\n")
  cat("Following Chen & Revels (2016) methodology\n")
  cat(strrep("=", 70), "\n")
  
  # Configuration
  n_rows <- 1000000
  n_elements <- 10000000
  n_random_reads <- 10000
  n_runs <- 10
  
  results <- list()
  
  # Task 1: CSV Write
  cat("\n[1/5] CSV Write (", n_rows, " rows)...\n", sep="")
  times <- replicate(n_runs, benchmark_csv_write(n_rows))
  results$csv_write <- list(
    min = min(times),              # PRIMARY (Chen & Revels 2016)
    mean = mean(times),
    median = median(times),
    std = sd(times),
    max = max(times),
    all_times = as.list(times)
  )
  cat("  ✓ Min:    ", sprintf("%.4f", results$csv_write$min), "s (PRIMARY)\n", sep="")
  cat("    Mean:   ", sprintf("%.4f", results$csv_write$mean), "s ± ", 
      sprintf("%.4f", results$csv_write$std), "s\n", sep="")
  cat("    Median: ", sprintf("%.4f", results$csv_write$median), "s\n", sep="")
  
  # Task 2: CSV Read
  cat("\n[2/5] CSV Read (", n_rows, " rows)...\n", sep="")
  times <- replicate(n_runs, benchmark_csv_read())
  results$csv_read <- list(
    min = min(times),
    mean = mean(times),
    median = median(times),
    std = sd(times),
    max = max(times),
    all_times = as.list(times)
  )
  cat("  ✓ Min:    ", sprintf("%.4f", results$csv_read$min), "s (PRIMARY)\n", sep="")
  cat("    Mean:   ", sprintf("%.4f", results$csv_read$mean), "s ± ", 
      sprintf("%.4f", results$csv_read$std), "s\n", sep="")
  
  # Task 3: Binary Write
  cat("\n[3/5] Binary Write (", n_elements, " elements)...\n", sep="")
  times <- replicate(n_runs, benchmark_binary_write(n_elements))
  results$binary_write <- list(
    min = min(times),
    mean = mean(times),
    median = median(times),
    std = sd(times),
    max = max(times),
    all_times = as.list(times)
  )
  cat("  ✓ Min:    ", sprintf("%.4f", results$binary_write$min), "s (PRIMARY)\n", sep="")
  cat("    Mean:   ", sprintf("%.4f", results$binary_write$mean), "s ± ", 
      sprintf("%.4f", results$binary_write$std), "s\n", sep="")
  
  # Task 4: Binary Read
  cat("\n[4/5] Binary Read (", n_elements, " elements)...\n", sep="")
  times <- replicate(n_runs, benchmark_binary_read())
  results$binary_read <- list(
    min = min(times),
    mean = mean(times),
    median = median(times),
    std = sd(times),
    max = max(times),
    all_times = as.list(times)
  )
  cat("  ✓ Min:    ", sprintf("%.4f", results$binary_read$min), "s (PRIMARY)\n", sep="")
  cat("    Mean:   ", sprintf("%.4f", results$binary_read$mean), "s ± ", 
      sprintf("%.4f", results$binary_read$std), "s\n", sep="")
  
  # Task 5: Random Access
  cat("\n[5/5] Random Access (", n_random_reads, " reads)...\n", sep="")
  times <- replicate(n_runs, benchmark_random_access(n_random_reads))
  results$random_access <- list(
    min = min(times),
    mean = mean(times),
    median = median(times),
    std = sd(times),
    max = max(times),
    all_times = as.list(times)
  )
  cat("  ✓ Min:    ", sprintf("%.4f", results$random_access$min), "s (PRIMARY)\n", sep="")
  cat("    Mean:   ", sprintf("%.4f", results$random_access$mean), "s ± ", 
      sprintf("%.4f", results$random_access$std), "s\n", sep="")
  
  # Save results
  cat("\n", strrep("=", 70), "\n", sep="")
  cat("SAVING RESULTS...\n")
  cat(strrep("=", 70), "\n")
  
  output <- list(
    language = "R",
    r_version = as.character(getRversion()),
    data.table_version = as.character(packageVersion("data.table")),
    csv_rows = n_rows,
    binary_elements = n_elements,
    random_reads = n_random_reads,
    n_runs = n_runs,
    methodology = "Chen & Revels (2016): minimum as primary estimator",
    results = results
  )
  
  write_json(output, "results/io_ops_r.json", pretty = TRUE, auto_unbox = TRUE)
  
  cat("✓ Results saved to: results/io_ops_r.json\n")
  cat("\nPrimary metrics (MINIMUM execution time):\n")
  cat("  CSV write:      ", sprintf("%.4f", results$csv_write$min), "s\n", sep="")
  cat("  CSV read:       ", sprintf("%.4f", results$csv_read$min), "s\n", sep="")
  cat("  Binary write:   ", sprintf("%.4f", results$binary_write$min), "s\n", sep="")
  cat("  Binary read:    ", sprintf("%.4f", results$binary_read$min), "s\n", sep="")
  cat("  Random access:  ", sprintf("%.4f", results$random_access$min), "s\n", sep="")
  
  # Cleanup
  if (file.exists("data/benchmark_output.csv")) file.remove("data/benchmark_output.csv")
  if (file.exists("data/benchmark_binary.bin")) file.remove("data/benchmark_binary.bin")
}

main()
