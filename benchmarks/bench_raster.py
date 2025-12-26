import rasterio, numpy as np, scipy.ndimage
from rasterio.windows import Window

print("🔵 [PYTHON] Raster: Focal Convolution (Slope)")

with rasterio.open("data/landsat_sample_cog.tif") as src:
    # 1. READ LARGE WINDOW
    w = Window(src.width//4, src.height//4, 3000, 3000)
    data = src.read(1, window=w).astype('float32')

    # 2. FOCAL OPERATION (Gradient/Slope Simulation)
    # Using Sobel filter forces looking at all 8 neighbors per pixel
    sx = scipy.ndimage.sobel(data, axis=0, mode='constant')
    sy = scipy.ndimage.sobel(data, axis=1, mode='constant')
    slope = np.hypot(sx, sy)

    # 3. SAVE
    profile = src.profile
    profile.update(width=3000, height=3000, dtype='float32')
    with rasterio.open("results/py_slope.tif", 'w', **profile) as dst:
        dst.write(slope, 1)
print("✅ Complete")
