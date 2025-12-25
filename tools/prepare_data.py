import os, urllib.request, zipfile, zarr, numpy as np

DATA_DIR = "data"
os.makedirs(DATA_DIR, exist_ok=True)

# 1. VECTOR: Natural Earth
VEC_URL = "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places.zip"
VEC_FILE = os.path.join(DATA_DIR, "ne_10m_populated_places.shp")
# 2. RASTER: Landsat Sample
RAS_URL = "https://github.com/cogeo/cog-spec/raw/master/examples/20200101_cog.tif"
RAS_FILE = os.path.join(DATA_DIR, "landsat_cog.tif")
# 3. HYPERSPECTRAL: Synthetic 5GB Cube
ZARR_PATH = os.path.join(DATA_DIR, "aviris_stress.zarr")
HSI_SHAPE = (224, 10000, 500)

def prepare():
    if not os.path.exists(VEC_FILE):
        print("⬇️ Downloading Vector Data...")
        zip_path = os.path.join(DATA_DIR, "temp.zip")
        urllib.request.urlretrieve(VEC_URL, zip_path)
        with zipfile.ZipFile(zip_path, 'r') as z: z.extractall(DATA_DIR)
        os.remove(zip_path)

    if not os.path.exists(RAS_FILE):
        print("⬇️ Downloading Raster Data...")
        urllib.request.urlretrieve(RAS_URL, RAS_FILE)

    if not os.path.exists(ZARR_PATH):
        print(f"🔥 Generating {HSI_SHAPE} Stress Cube (~4.5 GB)...")
        store = zarr.DirectoryStore(ZARR_PATH)
        root = zarr.group(store=store, overwrite=True)
        dset = root.create_dataset('reflectance', shape=HSI_SHAPE, chunks=(224, 512, 512), dtype='float32')
        dset.attrs['desc'] = 'Synthetic AVIRIS-NG Twin'
        print("✅ Stress Data Ready.")

if __name__ == "__main__":
    prepare()
