
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
library(data.table)
library(jsonlite)

benchmark_csv_write <- function(n_rows = 1000000) {
  df <- data.table(
    lat = runif(n_rows, -90, 90),
    lon = runif(n_rows, -180, 180),
    device_id = sample(1:10000, n_rows, replace = TRUE)
  )
  output_path <- file.path(DATA_DIR, "io_test_r.csv")
  t_start <- Sys.time()
  fwrite(df, output_path)
  t_end <- Sys.time()
  return(as.numeric(t_end - t_start, units = "secs"))
}

benchmark_csv_read <- function() {
  input_path <- file.path(DATA_DIR, "io_test_r.csv")
  t_start <- Sys.time()
  df <- fread(input_path)
  t_end <- Sys.time()
  return(as.numeric(t_end - t_start, units = "secs"))
}

main <- function() {
  cat("R - I/O Operations Benchmark (Standardized)\n")
  n_runs <- 30
  n_warmup <- 5
  
  # Warmup
  for(i in 1:n_warmup) benchmark_csv_write(100000)
  
  # Measured Runs
  write_times <- replicate(n_runs, benchmark_csv_write(1000000))
  read_times <- replicate(n_runs, benchmark_csv_read())
  
  results <- list(
    language = "r",
    scenario = "io_ops",
    csv_write = list(min = min(write_times), mean = mean(write_times)),
    csv_read = list(min = min(read_times), mean = mean(read_times))
  )
  write_json(results, "results/io_ops_r.json", auto_unbox = TRUE, pretty = TRUE)
  cat("✓ Results saved to results/io_ops_r.json\n")
}
main()