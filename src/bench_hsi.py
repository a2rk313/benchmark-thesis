import time
import xarray as xr
import dask.array as da

FILE = "data/aviris_stress.zarr"

def main():
    # 1. OPEN (Lazy)
    ds = xr.open_zarr(FILE)
    data = ds['reflectance']

    print(f"Dataset Shape: {data.shape}")
    print(f"Dataset Size:  {data.nbytes / 1e9:.2f} GB")

    # 2. COMPUTE (Streaming)
    start = time.time()
    # Collapse Band Dimension (axis 0)
    # Dask will pull chunks, compute mean, discard chunk, repeat.
    result = data.mean(dim='dim_0').compute()
    elapsed = time.time() - start

    print(f"HSI Streaming Mean: {elapsed:.4f}s")

if __name__ == "__main__":
    main()
