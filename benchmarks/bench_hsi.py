import xarray as xr, numpy as np, pandas as pd

print("🟣 [PYTHON] HSI: Correlation Matrix")

# 1. LOAD
ds = xr.open_zarr("data/pavia.zarr")
# Shape: (X, Y, Band). We need (Pixels, Band)
# This reshape forces a massive memory shuffle
flat = ds['reflectance'].stack(pixel=("x", "y"))

# 2. CORRELATION MATRIX (Heavy Linear Algebra)
# Corrcoef on (Band, Pixel) -> Returns (Band, Band) matrix
# .data converts to numpy (triggering Dask compute)
matrix = np.corrcoef(flat.data)

# 3. SAVE
pd.DataFrame(matrix).to_csv("results/py_corr_matrix.csv")
print("✅ Complete")
