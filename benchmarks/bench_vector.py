import time, geopandas as gpd
FILE = "data/ne_10m_populated_places.shp"

def main():
    start = time.time()
    gdf = gpd.read_file(FILE)
    print(f"Read: {time.time()-start:.4f}s")
    start = time.time()
    _ = gdf.buffer(0.1)
    print(f"Buffer: {time.time()-start:.4f}s")

if __name__ == "__main__":
    main()
