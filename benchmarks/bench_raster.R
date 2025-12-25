library(terra)

FILE <- "data/landsat_cog.tif"

# Setup: Open handle (lazy)
r <- rast(FILE)
c_x <- ncol(r) / 2
c_y <- nrow(r) / 2

# Define extent for 512x512 window around center
# terra uses coordinates, we must convert indices to extent roughly
# Or easier: use crop with row/col indices
start <- Sys.time()

# crop by Row/Col indices (row, nrows, col, ncols)
w <- r[c_y:(c_y+511), c_x:(c_x+511), drop=FALSE]
# Force read values into memory
vals <- values(w)

elapsed <- as.numeric(Sys.time() - start)

cat(sprintf("COG Window Read: %.4fs\n", elapsed))
cat(sprintf("Pixel Sum:       %.0f\n", sum(vals, na.rm=TRUE)))
