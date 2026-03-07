#!/usr/bin/env Rscript
#===============================================================================
# Matrix Operations Benchmark - R Implementation
#===============================================================================

library(jsonlite)

benchmark_matrix_creation_transpose_reshape <- function(n = 2500) {
  start_time <- Sys.time()
  A <- matrix(rnorm(n * n), nrow = n, ncol = n)
  A <- t(A)
  new_rows <- as.integer(n * 3 / 5)
  new_cols <- as.integer(n * 5 / 3)
  dim(A) <- c(new_rows, new_cols)
  A <- t(A)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  return(elapsed)
}

benchmark_matrix_power <- function(n = 2500) {
  A <- matrix(rnorm(n * n), nrow = n, ncol = n)
  A <- abs(A) / 2.0
  start_time <- Sys.time()
  A_pow <- A ^ 10
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  return(elapsed)
}

benchmark_sorting <- function(n = 1000000) {
  arr <- rnorm(n)
  start_time <- Sys.time()
  arr_sorted <- sort(arr, method = "quick")
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  return(elapsed)
}

benchmark_crossproduct <- function(n = 2500) {
  A <- matrix(rnorm(n * n), nrow = n, ncol = n)
  start_time <- Sys.time()
  B <- crossprod(A)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  return(elapsed)
}

benchmark_determinant <- function(n = 2500) {
  A <- matrix(rnorm(n * n), nrow = n, ncol = n)
  start_time <- Sys.time()
  det_val <- det(A)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  return(elapsed)
}

main <- function() {
  cat(strrep("=", 70), "\n")
  cat("R - Matrix Operations Benchmark\n")
  cat(strrep("=", 70), "\n")
  
  n_matrix <- 2500
  n_sort <- 1000000
  n_runs <- 10
  
  results <- list()
  
  cat(sprintf("\n[1/5] Matrix Creation + Transpose + Reshape (%d×%d)...\n", n_matrix, n_matrix))
  times <- replicate(n_runs, benchmark_matrix_creation_transpose_reshape(n_matrix))
  results$matrix_creation <- list(mean = mean(times), std = sd(times), min = min(times), max = max(times))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", results$matrix_creation$mean, results$matrix_creation$std))
  
  cat(sprintf("\n[2/5] Matrix Exponentiation ^10 (%d×%d)...\n", n_matrix, n_matrix))
  times <- replicate(n_runs, benchmark_matrix_power(n_matrix))
  results$matrix_power <- list(mean = mean(times), std = sd(times), min = min(times), max = max(times))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", results$matrix_power$mean, results$matrix_power$std))
  
  cat(sprintf("\n[3/5] Sorting %s Random Values...\n", format(n_sort, big.mark = ",")))
  times <- replicate(n_runs, benchmark_sorting(n_sort))
  results$sorting <- list(mean = mean(times), std = sd(times), min = min(times), max = max(times))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", results$sorting$mean, results$sorting$std))
  
  cat(sprintf("\n[4/5] Cross-Product A'A (%d×%d)...\n", n_matrix, n_matrix))
  times <- replicate(n_runs, benchmark_crossproduct(n_matrix))
  results$crossproduct <- list(mean = mean(times), std = sd(times), min = min(times), max = max(times))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", results$crossproduct$mean, results$crossproduct$std))
  
  cat(sprintf("\n[5/5] Matrix Determinant (%d×%d)...\n", n_matrix, n_matrix))
  times <- replicate(n_runs, benchmark_determinant(n_matrix))
  results$determinant <- list(mean = mean(times), std = sd(times), min = min(times), max = max(times))
  cat(sprintf("  ✓ Mean: %.4fs ± %.4fs\n", results$determinant$mean, results$determinant$std))
  
  cat("\n", strrep("=", 70), "\n")
  cat("SAVING RESULTS...\n")
  cat(strrep("=", 70), "\n")
  
  output <- list(
    language = "R",
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    blas_library = sessionInfo()$BLAS,
    matrix_size = n_matrix,
    sorting_size = n_sort,
    n_runs = n_runs,
    results = results
  )
  
  write_json(output, "results/matrix_ops_r.json", auto_unbox = TRUE, pretty = TRUE)
  cat("✓ Results saved to: results/matrix_ops_r.json\n")
}

main()
