library(terra)

cat("🔵 [R] Raster: Focal Convolution (Slope)\n")

# 1. READ
r <- rast("data/landsat_sample_cog.tif")
e <- ext(r)
crop_ext <- ext(e[1] + (e[2]-e[1])/4, e[2] - (e[2]-e[1])/4, e[3] + (e[4]-e[3])/4, e[4] - (e[4]-e[3])/4)
r_crop <- crop(r, crop_ext)

# 2. FOCAL OPERATION (Slope/Terrain)
# terra::terrain calculates slope/aspect requiring 3x3 window neighborhood
slope <- terrain(r_crop, v="slope", neighbors=8)

# 3. SAVE
writeRaster(slope, "results/r_slope.tif", overwrite=TRUE)
cat("✅ Complete\n")
