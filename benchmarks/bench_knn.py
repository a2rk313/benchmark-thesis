import time
import geopandas as gpd
import numpy as np
from sklearn.neighbors import BallTree

FILE = "data/ne_10m_populated_places.shp"

def main():
    # Setup
    gdf = gpd.read_file(FILE)
    # Extract X/Y and duplicate 10x to create load (approx 73k points)
    coords = np.vstack([np.column_stack((gdf.geometry.x, gdf.geometry.y))] * 10)
    # Convert to radians for Haversine metric
    rads = np.radians(coords)

    print(f"Benchmarking KNN on {len(rads)} points...")

    # 1. INDEX (Write Stress)
    start_idx = time.time()
    # leaf_size affects cache locality. 40 is standard.
    tree = BallTree(rads, metric='haversine', leaf_size=40)
    idx_time = time.time() - start_idx

    # 2. QUERY (Read/Traverse Stress)
    start_query = time.time()
    # k=5 nearest neighbors
    dists, indices = tree.query(rads, k=5)
    query_time = time.time() - start_query

    print(f"Index Build: {idx_time:.4f}s")
    print(f"Query Time:  {query_time:.4f}s")

if __name__ == "__main__":
    main()
