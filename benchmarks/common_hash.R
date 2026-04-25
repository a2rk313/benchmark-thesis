
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
# =============================================================================
# Unified Hashing Utilities for R
# Uses SHA256 with consistent sampling for cross-language validation.
# =============================================================================

sample_array <- function(arr, n_samples = 100) {
  if (is.null(arr) || length(arr) == 0) {
    return(numeric(0))
  }
  flat <- as.numeric(arr)
  len <- length(flat)
  if (len <= n_samples) {
    return(flat)
  }
  # Use 0-indexed sampling to match Python (not 1-indexed)
  indices <- floor(seq(0, len - 1, length.out = n_samples))
  return(flat[indices + 1])  # R is 1-indexed, so add 1
}

round_val <- function(v, precision = 6) {
  if (is.numeric(v)) {
    return(round(v, precision))
  }
  return(v)
}

generate_hash <- function(data, n_samples = 100) {
  if (is.null(data)) {
    return(paste0(rep("0", 16), collapse = ""))
  }
  
  if (is.list(data) && !is.data.frame(data)) {
    keys <- sort(names(data))
    items <- lapply(keys, function(k) {
      v <- data[[k]]
      if (is.numeric(v) && length(v) > 1) {
        sampled <- sample_array(v, n_samples)
        list(key = k, values = sapply(sampled, round_val))
      } else {
        list(key = k, values = round_val(v))
      }
    })
    content <- jsonlite::toJSON(items, auto_unbox = FALSE, pretty = FALSE)
  } else if (is.numeric(data)) {
    if (length(data) > 1) {
      sampled <- sample_array(data, n_samples)
      content <- jsonlite::toJSON(sapply(sampled, round_val), auto_unbox = FALSE)
    } else {
      content <- jsonlite::toJSON(round_val(data), auto_unbox = TRUE)
    }
  } else {
    content <- as.character(data)
  }
  
  h <- digest::digest(content, algo = "sha256", serialize = FALSE)
  return(substr(h, 1, 16))
}
