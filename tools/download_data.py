import os, urllib.request, zipfile, scipy.io, xarray as xr, shutil, time

DATA_DIR = "data"
os.makedirs(DATA_DIR, exist_ok=True)
ZARR_PATH = os.path.join(DATA_DIR, "pavia.zarr")

DATASETS = {
    "vector": {
        "url": "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places.zip",
        "file": "ne_10m_populated_places.shp"
    },
    "countries": {
        "url": "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip",
        "file": "ne_10m_admin_0_countries.shp"
    },
    "raster": {
        # FIXED: Updated 'master' to 'main' and used raw.githubusercontent.com
        "url": "https://raw.githubusercontent.com/cogeo/cog-spec/main/examples/20200101_cog.tif",
        "file": "landsat_sample_cog.tif"
    },
    "hsi": {
        "url": "http://www.ehu.eus/ccwintco/uploads/e/ee/PaviaU.mat",
        "file": "PaviaU.mat"
    }
}

def download_with_retry(url, dest, retries=3):
    for i in range(retries):
        try:
            print(f"⬇️ Downloading {dest} (Attempt {i+1})...")
            # Fake User-Agent to avoid 403 Forbidden on some servers
            req = urllib.request.Request(
                url,
                data=None,
                headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
            )
            with urllib.request.urlopen(req) as response, open(dest, 'wb') as out_file:
                shutil.copyfileobj(response, out_file)
            return
        except Exception as e:
            print(f"⚠️ Error downloading {url}: {e}")
            time.sleep(2)
            if i == retries - 1:
                raise e

def prepare():
    for key, info in DATASETS.items():
        dest = os.path.join(DATA_DIR, info["file"])
        # Handle Zip extraction logic
        if info["url"].endswith(".zip"):
            if not os.path.exists(dest):
                zip_name = "temp.zip"
                download_with_retry(info["url"], zip_name)
                print(f"📦 Extracting {key}...")
                with zipfile.ZipFile(zip_name, 'r') as z:
                    z.extractall(DATA_DIR)
                os.remove(zip_name)
        else:
            if not os.path.exists(dest):
                download_with_retry(info["url"], dest)

    # Convert HSI to Zarr
    if not os.path.exists(ZARR_PATH):
        print("📦 Converting PaviaU .mat to Zarr Cube...")
        try:
            mat = scipy.io.loadmat(os.path.join(DATA_DIR, "PaviaU.mat"))
            ds = xr.Dataset({"reflectance": (("x", "y", "band"), mat['paviaU'])})
            ds.to_zarr(ZARR_PATH, mode='w', computed=True)
            print("✅ Zarr Cube Created.")
        except Exception as e:
            print(f"⚠️ Failed to convert HSI: {e}")
            # Don't crash build if HSI fails, just skip it (optional safety)
            pass

if __name__ == "__main__":
    prepare()
