library(stars)
library(dplyr)

FILE <- "data/aviris_stress.zarr"

# 1. OPEN (Lazy Proxy)
# stars proxy object points to the Zarr on disk without loading
cube <- read_stars(FILE, proxy = TRUE)

cat(sprintf("Dataset Loaded (Proxy)\n"))

start <- Sys.time()

# 2. COMPUTE
# st_apply automatically chunks operations on proxy objects
# MARGIN 2:3 means keep x/y (dims 2 and 3), collapse dim 1 (band)
# Note: Dimension names might depend on how Zarr was written.
# We assume standard order. If error, check print(cube) dimensions.
result <- st_apply(cube, MARGIN = c("dim_1", "dim_2"), FUN = mean)

# Force computation by pulling result into memory
res_mem <- as.data.frame(result)

elapsed <- as.numeric(Sys.time() - start)
cat(sprintf("HSI Streaming Mean: %.4fs\n", elapsed))
