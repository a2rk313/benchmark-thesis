#!/usr/bin/env Rscript
################################################################################
# SCENARIO A.2: Hyperspectral SAM – R Implementation (Cuprite dataset)
################################################################################

suppressPackageStartupMessages({
  library(R.matlab)
  library(jsonlite)
  library(digest)
})

spectral_angle_mapper <- function(pixel_matrix, reference_spectrum) {
  epsilon <- 1e-8
  dot_products <- pixel_matrix %*% reference_spectrum
  pixel_norms <- sqrt(rowSums(pixel_matrix^2))
  ref_norm <- sqrt(sum(reference_spectrum^2))
  cos_angles <- dot_products / (pixel_norms * ref_norm + epsilon)
  cos_angles <- pmin(pmax(cos_angles, -1), 1)
  angles <- acos(cos_angles)
  return(as.vector(angles))
}

main <- function() {
  cat(strrep("=", 70), "\n")
  cat("R - Scenario A.2: Hyperspectral SAM (Cuprite)\n")
  cat(strrep("=", 70), "\n")

  # ---------------------------------------------------------------------------
  # 1. Load Cuprite dataset
  # ---------------------------------------------------------------------------
  cat("\n[1/5] Loading Cuprite dataset...\n")
  mat_data <- readMat("data/Cuprite.mat")
  # Find the first non-metadata element
  data <- mat_data[[1]]  # shape: (bands, rows, cols)
  dims <- dim(data)
  n_bands <- dims[1]
  n_rows <- dims[2]
  n_cols <- dims[3]
  cat(sprintf("  ✓ Dataset shape: %d bands, %d×%d pixels\n", n_bands, n_rows, n_cols))

  set.seed(42)
  reference_spectrum <- runif(n_bands)
  reference_spectrum <- reference_spectrum / sqrt(sum(reference_spectrum^2))
  ref_hash <- substr(digest(reference_spectrum, algo = "sha256"), 1, 16)
  cat(sprintf("  ✓ Reference spectrum hash: %s\n", ref_hash))

  # ---------------------------------------------------------------------------
  # 2. Process in chunks
  # ---------------------------------------------------------------------------
  cat("\n[2/5] Processing hyperspectral data (chunked)...\n")
  chunk_size <- 256
  sam_results <- c()
  pixels_processed <- 0
  chunks_processed <- 0

  for (r_start in seq(1, n_rows, by = chunk_size)) {
    r_end <- min(r_start + chunk_size - 1, n_rows)
    for (c_start in seq(1, n_cols, by = chunk_size)) {
      c_end <- min(c_start + chunk_size - 1, n_cols)
      # Extract chunk: (bands, h, w)
      chunk <- data[, r_start:r_end, c_start:c_end, drop = FALSE]
      # Reshape to (pixels, bands)
      pixel_matrix <- matrix(chunk, nrow = n_bands, byrow = FALSE)
      pixel_matrix <- t(pixel_matrix)  # now (pixels, bands)
      sam_angles <- spectral_angle_mapper(pixel_matrix, reference_spectrum)
      sam_results <- c(sam_results, sam_angles)
      pixels_processed <- pixels_processed + nrow(pixel_matrix)
      chunks_processed <- chunks_processed + 1
      if (chunks_processed %% 10 == 0) {
        cat(sprintf("\r    Processed %d chunks (%s pixels)...",
                    chunks_processed, format(pixels_processed, big.mark = ",")))
      }
    }
  }
  cat(sprintf("\r    Processed %d chunks (%s pixels)... Done!\n",
              chunks_processed, format(pixels_processed, big.mark = ",")))

  # ---------------------------------------------------------------------------
  # 3. Statistics
  # ---------------------------------------------------------------------------
  cat("\n[3/5] Computing statistics...\n")
  mean_sam <- mean(sam_results)
  median_sam <- median(sam_results)
  std_sam <- sd(sam_results)
  min_sam <- min(sam_results)
  max_sam <- max(sam_results)
  cat(sprintf("  ✓ Mean SAM: %.6f rad (%.2f°)\n", mean_sam, mean_sam * 180 / pi))
  cat(sprintf("  ✓ Median SAM: %.6f rad\n", median_sam))
  cat(sprintf("  ✓ Std Dev: %.6f rad\n", std_sam))

  # ---------------------------------------------------------------------------
  # 4. Validation
  # ---------------------------------------------------------------------------
  cat("\n[4/5] Generating validation data...\n")
  result_str <- sprintf("%.8f_%d_%.8f", mean_sam, pixels_processed, median_sam)
  result_hash <- substr(digest(result_str, algo = "sha256"), 1, 16)
  cat(sprintf("  ✓ Validation hash: %s\n", result_hash))

  results <- list(
    language = "r",
    scenario = "hyperspectral_sam",
    pixels_processed = pixels_processed,
    chunks_processed = chunks_processed,
    n_bands = n_bands,
    mean_sam_rad = mean_sam,
    median_sam_rad = median_sam,
    std_sam_rad = std_sam,
    min_sam_rad = min_sam,
    max_sam_rad = max_sam,
    mean_sam_deg = mean_sam * 180 / pi,
    validation_hash = result_hash,
    reference_hash = ref_hash
  )

  dir.create("validation", showWarnings = FALSE)
  write_json(results, "validation/raster_r_results.json", pretty = TRUE, auto_unbox = TRUE)
  cat("\n  ✓ Results saved to validation/raster_r_results.json\n")
  cat(strrep("=", 70), "\n")
  return(0)
}

quit(status = main())
