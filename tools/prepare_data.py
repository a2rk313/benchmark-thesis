import os, urllib.request, zipfile, scipy.io, xarray as xr, shutil

DATA_DIR = "data"
os.makedirs(DATA_DIR, exist_ok=True)
ZARR_PATH = os.path.join(DATA_DIR, "pavia.zarr")

DATASETS = {
    "vector": {"url": "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places.zip", "file": "ne_10m_populated_places.shp"},
    "countries": {"url": "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip", "file": "ne_10m_admin_0_countries.shp"},
    "raster": {"url": "https://github.com/cogeo/cog-spec/raw/master/examples/20200101_cog.tif", "file": "landsat_sample_cog.tif"},
    "hsi":    {"url": "http://www.ehu.eus/ccwintco/uploads/e/ee/PaviaU.mat", "file": "PaviaU.mat"}
}

def prepare():
    for key, info in DATASETS.items():
        dest = os.path.join(DATA_DIR, info["file"])
        if not os.path.exists(dest):
            print(f"⬇️ Downloading {key}...")
            if info["url"].endswith(".zip"):
                urllib.request.urlretrieve(info["url"], "temp.zip")
                with zipfile.ZipFile("temp.zip", 'r') as z: z.extractall(DATA_DIR)
                os.remove("temp.zip")
            else:
                urllib.request.urlretrieve(info["url"], dest)

    if not os.path.exists(ZARR_PATH):
        print("📦 Converting PaviaU .mat to Zarr Cube...")
        mat = scipy.io.loadmat(os.path.join(DATA_DIR, "PaviaU.mat"))
        ds = xr.Dataset({"reflectance": (("x", "y", "band"), mat['paviaU'])})
        ds.to_zarr(ZARR_PATH, mode='w', computed=True)
        print("✅ Zarr Cube Created.")

if __name__ == "__main__":
    prepare()
