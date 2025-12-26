import geopandas as gpd
import os

print("🟢 [PYTHON] Vector: Reprojection & Buffer Stress")

# 1. LOAD (WGS84)
cities = gpd.read_file("data/ne_10m_populated_places.shp")
countries = gpd.read_file("data/ne_10m_admin_0_countries.shp")

# 2. FILTER & JOIN
large_countries = countries[countries['POP_EST'] > 10_000_000]
selected_cities = gpd.sjoin(cities, large_countries, how="inner", predicate="within")

# 3. HEAVY: REPROJECT TO METERS (Web Mercator EPSG:3857)
# This forces the PROJ engine to transform coordinates
selected_cities = selected_cities.to_crs(epsg=3857)

# 4. BUFFER (10km) & AREA CALC
# Buffering in meters is computationally heavier than degrees
selected_cities['geometry'] = selected_cities.buffer(10000)
selected_cities['area_km2'] = selected_cities.area / 1e6

# 5. SAVE
os.makedirs("results", exist_ok=True)
selected_cities.to_file("results/py_site_selection.gpkg", driver="GPKG")
print("✅ Complete")
