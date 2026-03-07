#!/usr/bin/env python3
"""
===============================================================================
Data Generation: Real-World Vector Datasets
===============================================================================
Generates high-quality geospatial test data for benchmarking:
1. Natural Earth Admin-0 Countries (complex polygons with high vertex counts)
2. 1 Million GPS points (global distribution with realistic spatial patterns)
===============================================================================
"""

import geopandas as gpd
import numpy as np
import pandas as pd
from pathlib import Path
import urllib.request
import zipfile
import os
import hashlib

def download_natural_earth():
    """
    Download Natural Earth Admin-0 Countries (1:10m resolution)
    This provides polygons with realistic complexity (fjords, islands, etc.)
    """
    print("\n[1/2] Downloading Natural Earth Countries (1:10m)...")
    
    url = "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip"
    zip_path = "data/ne_10m_admin_0_countries.zip"
    extract_dir = "data/natural_earth"
    
    Path("data").mkdir(exist_ok=True)
    Path(extract_dir).mkdir(exist_ok=True)
    
    if not os.path.exists(zip_path):
        print(f"  Downloading from {url}...")
        urllib.request.urlretrieve(url, zip_path)
        print(f"  ✓ Downloaded {os.path.getsize(zip_path) / (1024**2):.2f} MB")
    else:
        print(f"  ✓ Using cached download")
    
    print("  Extracting shapefile...")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_dir)
    
    print("  Processing data...")
    countries = gpd.read_file(f"{extract_dir}/ne_10m_admin_0_countries.shp")
    
    # Keep only columns that exist (some may have changed names)
    available_cols = countries.columns.tolist()
    cols_to_keep = ['NAME', 'POP_EST', 'CONTINENT', 'geometry']
    cols_present = [col for col in cols_to_keep if col in available_cols]
    countries = countries[cols_present]
    
    # Explode multipolygons to separate features (increases complexity)
    countries = countries.explode(index_parts=True).reset_index(drop=True)
    
    output_path = "data/natural_earth_countries.gpkg"
    countries.to_file(output_path, driver="GPKG")
    
    # Calculate statistics
    total_vertices = sum(
        len(geom.exterior.coords) if geom.geom_type == 'Polygon' 
        else sum(len(part.exterior.coords) for part in geom.geoms)
        for geom in countries.geometry
    )
    
    print(f"\n  ✓ Saved to {output_path}")
    print(f"  ✓ Features: {len(countries)}")
    print(f"  ✓ Total vertices: {total_vertices:,}")
    print(f"  ✓ Average vertices per feature: {total_vertices / len(countries):.0f}")
    if 'NAME' in countries.columns:
        most_complex = countries.loc[countries.geometry.apply(lambda g: len(g.exterior.coords) if g.geom_type == 'Polygon' else 0).idxmax()]
        print(f"  ✓ Most complex: {most_complex['NAME']}")
    
    return countries

def generate_gps_points(n_points=1_000_000, seed=42):
    """
    Generate 1 million GPS points with realistic spatial distribution
    Uses weighted sampling to concentrate points near populated areas
    """
    print(f"\n[2/2] Generating {n_points:,} GPS points...")
    
    np.random.seed(seed)
    
    # Desired percentages (must sum to 1.0)
    frac_nh = 0.40   # Northern Hemisphere cities
    frac_global = 0.30
    frac_coastal = 0.20
    frac_sh = 0.10   # Southern Hemisphere cities
    
    # Calculate exact counts (floor)
    n_nh = int(n_points * frac_nh)
    n_global = int(n_points * frac_global)
    n_coastal = int(n_points * frac_coastal)
    n_sh = int(n_points * frac_sh)
    
    # The sum may be less than n_points; we will fill the remainder with global points
    remainder = n_points - (n_nh + n_global + n_coastal + n_sh)
    n_global += remainder   # add the remainder here
    
    points_data = []
    
    # Northern Hemisphere cities (40%)
    nh_centers = [
        (40.7128, -74.0060),   # New York
        (51.5074, -0.1278),    # London
        (35.6762, 139.6503),   # Tokyo
        (28.6139, 77.2090),    # Delhi
        (31.2304, 121.4737),   # Shanghai
    ]
    per_cluster = n_nh // len(nh_centers)
    for lat_c, lon_c in nh_centers:
        lats = np.random.normal(lat_c, 2.0, per_cluster)
        lons = np.random.normal(lon_c, 2.0, per_cluster)
        points_data.extend(list(zip(lats, lons)))
    # Add any leftover to the first cluster
    leftover_nh = n_nh - per_cluster * len(nh_centers)
    if leftover_nh > 0:
        lat_c, lon_c = nh_centers[0]
        lats = np.random.normal(lat_c, 2.0, leftover_nh)
        lons = np.random.normal(lon_c, 2.0, leftover_nh)
        points_data.extend(list(zip(lats, lons)))
    
    # Global uniform (30% + remainder)
    lats_global = np.random.uniform(-90, 90, n_global)
    lons_global = np.random.uniform(-180, 180, n_global)
    points_data.extend(list(zip(lats_global, lons_global)))
    
    # Coastal regions (20%)
    coastal_groups = 3
    per_group = n_coastal // coastal_groups
    # Equatorial
    lats = np.random.normal(0, 20, per_group)
    lons = np.random.uniform(-180, 180, per_group)
    points_data.extend(list(zip(lats, lons)))
    # Mid-latitude N
    lats = np.random.normal(45, 10, per_group)
    lons = np.random.uniform(-180, 180, per_group)
    points_data.extend(list(zip(lats, lons)))
    # Mid-latitude S
    lats = np.random.normal(-35, 10, per_group)
    lons = np.random.uniform(-180, 180, per_group)
    points_data.extend(list(zip(lats, lons)))
    leftover_coastal = n_coastal - per_group * coastal_groups
    if leftover_coastal > 0:
        lats = np.random.normal(0, 20, leftover_coastal)
        lons = np.random.uniform(-180, 180, leftover_coastal)
        points_data.extend(list(zip(lats, lons)))
    
    # Southern Hemisphere cities (10%)
    sh_centers = [
        (-33.8688, 151.2093),  # Sydney
        (-23.5505, -46.6333),  # São Paulo
        (-26.2041, 28.0473),   # Johannesburg
    ]
    per_cluster = n_sh // len(sh_centers)
    for lat_c, lon_c in sh_centers:
        lats = np.random.normal(lat_c, 2.0, per_cluster)
        lons = np.random.normal(lon_c, 2.0, per_cluster)
        points_data.extend(list(zip(lats, lons)))
    leftover_sh = n_sh - per_cluster * len(sh_centers)
    if leftover_sh > 0:
        lat_c, lon_c = sh_centers[0]
        lats = np.random.normal(lat_c, 2.0, leftover_sh)
        lons = np.random.normal(lon_c, 2.0, leftover_sh)
        points_data.extend(list(zip(lats, lons)))
    
    # Convert to DataFrame (first n_points)
    # Because we added exactly n_points, this slice is safe
    df = pd.DataFrame(points_data[:n_points], columns=['lat', 'lon'])
    
    # Clip to valid ranges
    df['lat'] = df['lat'].clip(-90, 90)
    df['lon'] = df['lon'].clip(-180, 180)
    
    # Add synthetic attributes
    df['device_id'] = np.random.randint(1, 10000, n_points)
    df['timestamp'] = pd.date_range('2024-01-01', periods=n_points, freq='s')
    df['accuracy_m'] = np.random.exponential(10, n_points).clip(1, 100)
    
    output_path = "data/gps_points_1m.csv"
    df.to_csv(output_path, index=False)
    
    file_hash = hashlib.md5(open(output_path, 'rb').read()).hexdigest()
    
    print(f"\n  ✓ Saved to {output_path}")
    print(f"  ✓ Points: {len(df):,}")
    print(f"  ✓ Lat range: [{df['lat'].min():.2f}, {df['lat'].max():.2f}]")
    print(f"  ✓ Lon range: [{df['lon'].min():.2f}, {df['lon'].max():.2f}]")
    print(f"  ✓ File size: {os.path.getsize(output_path) / (1024**2):.2f} MB")
    print(f"  ✓ MD5 checksum: {file_hash}")
    
    return df

def main():
    print("=" * 70)
    print("VECTOR DATA GENERATION: Natural Earth + GPS Points")
    print("=" * 70)
    
    Path("data").mkdir(exist_ok=True)
    
    countries = download_natural_earth()
    points = generate_gps_points()
    
    print("\n" + "=" * 70)
    print("DATA GENERATION COMPLETE")
    print("=" * 70)
    print("\nFiles created:")
    print("  1. data/natural_earth_countries.gpkg (polygons)")
    print("  2. data/gps_points_1m.csv (points)")
    print("\nYou can now run the vector benchmarks.")
    print("=" * 70)

if __name__ == "__main__":
    main()
