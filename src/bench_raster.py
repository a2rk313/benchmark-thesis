import time
import rasterio
from rasterio.windows import Window

FILE = "data/landsat_cog.tif"

def main():
    # We open the file (Metadata read only)
    with rasterio.open(FILE) as src:
        # Calculate center window
        c_x = src.width // 2
        c_y = src.height // 2
        w = Window(c_x, c_y, 512, 512)

        # 1. READ (Seek + Read)
        # This tests how fast the driver jumps to the byte offset
        start = time.time()
        data = src.read(1, window=w)
        elapsed = time.time() - start

        print(f"COG Window Read: {elapsed:.4f}s")
        print(f"Pixel Sum:       {data.sum()}") # Prevent dead code elimination

if __name__ == "__main__":
    main()
