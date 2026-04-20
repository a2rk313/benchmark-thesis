#!/usr/bin/env Rscript
# Tests file I/O performance for CSV and binary formats
# Using data.table for fair comparison with Julia/Python

library(data.table)
library(jsonlite)
library(digest)

benchmark_csv_write <- function(n_rows = 1000000) {
  df <- data.table(
    id = 1:n_rows,
    value1 = rnorm(n_rows),
    value2 = runif(n_rows),
    category = sample(c("A", "B", "C", "D"), n_rows, replace = TRUE)
  )
  
  output_path <- "data/io_test_r.csv"
  t_start <- Sys.time()
  # Using fwrite (fast) instead of write.csv (slow)
  fwrite(df, output_path)
  t_end <- Sys.time()
  
  file_size_mb <- file.info(output_path)$size / (1024^2)
  return(list(time = as.numeric(t_end - t_start, units = "secs"), file_size_mb = file_size_mb))
}

benchmark_csv_read <- function() {
  input_path <- "data/io_test_r.csv"
  t_start <- Sys.time()
  # Using fread (fast) instead of read.csv (slow)
  df <- fread(input_path)
  t_end <- Sys.time()
  
  return(list(time = as.numeric(t_end - t_start, units = "secs"), rows = nrow(df)))
}

benchmark_binary_write <- function(n_values = 1000000) {
  data <- rnorm(n_values)
  output_path <- "data/io_test_r.bin"
  
  t_start <- Sys.time()
  writeBin(data, output_path)
  t_end <- Sys.time()
  
  file_size_mb <- file.info(output_path)$size / (1024^2)
  return(list(time = as.numeric(t_end - t_start, units = "secs"), file_size_mb = file_size_mb))
}

benchmark_binary_read <- function() {
  input_path <- "data/io_test_r.bin"
  t_start <- Sys.time()
  data <- readBin(input_path, what = "numeric", n = 1000000)
  t_end <- Sys.time()
  
  return(list(time = as.numeric(t_end - t_start, units = "secs"), n = length(data)))
}

# Main execution loop
n_csv_rows <- 1000000
n_binary_values <- 1000000
results <- list()

cat("\n[1/4] CSV Write (fwrite)...\n")
t1 <- benchmark_csv_write(n_csv_rows)
cat(sprintf("  ✓ Completed in %.4fs\n", t1$time))

cat("\n[2/4] CSV Read (fread)...\n")
t2 <- benchmark_csv_read()
cat(sprintf("  ✓ Completed in %.4fs\n", t2$time))

results <- list(
  language = "r",
  scenario = "io_ops",
  csv_write_s = t1$time,
  csv_read_s = t2$time,
  csv_size_mb = t1$file_size_mb
)

write_json(results, "results/io_ops_r.json", auto_unbox = TRUE, pretty = TRUE)
