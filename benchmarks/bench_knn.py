from sklearn.neighbors import KDTree
import geopandas as gpd, numpy as np, pandas as pd

print("🟠 [PYTHON] KNN: Density Search (K=50)")

gdf = gpd.read_file("data/ne_10m_populated_places.shp")
coords = np.array(list(zip(gdf.geometry.x, gdf.geometry.y)))

# 1. INDEX
tree = KDTree(coords)

# 2. QUERY 50 NEIGHBORS (Heavy Branching)
dists, inds = tree.query(coords, k=50)

# 3. CALCULATE MEAN DISTANCE (Density Metric)
mean_dist = np.mean(dists, axis=1)

pd.DataFrame(mean_dist).to_csv("results/py_knn_density.csv")
print("✅ Complete")
