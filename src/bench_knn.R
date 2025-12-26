library(sf)
library(FNN) # Fast Nearest Neighbors (wraps C++ library)

FILE <- "data/ne_10m_populated_places.shp"

# Setup
gdf <- st_read(FILE, quiet=TRUE)
coords <- st_coordinates(gdf)
# Duplicate 10x
coords <- do.call(rbind, replicate(10, coords, simplify=FALSE))

cat(sprintf("Benchmarking KNN on %d points...\n", nrow(coords)))

# FNN get.knn usually does both build and query in one optimized C++ call.
# This is a fair comparison because usually you want the result immediately.
start <- Sys.time()

# algorithm="kd_tree" forces tree construction
res <- get.knn(coords, k=5, algorithm="kd_tree")

elapsed <- as.numeric(Sys.time() - start)

# We can't easily split Build/Query in FNN R wrapper, so we report total.
cat(sprintf("Total KNN (Build+Query): %.4fs\n", elapsed))
