library(sf)

FILE <- "data/ne_10m_populated_places.shp"

# 1. READ (I/O)
start_read <- Sys.time()
# quiet=TRUE suppresses the header printout for cleaner logs
gdf <- st_read(FILE, quiet=TRUE)
read_time <- as.numeric(Sys.time() - start_read)

# 2. COMPUTE (CPU FPU)
start_compute <- Sys.time()
# dist = 0.1 degrees
buffered <- st_buffer(gdf, dist=0.1)
compute_time <- as.numeric(Sys.time() - start_compute)

cat(sprintf("Vector Read:    %.4fs\n", read_time))
cat(sprintf("Vector Buffer:  %.4fs\n", compute_time))
cat(sprintf("Total Geoms:    %d\n", nrow(gdf)))
