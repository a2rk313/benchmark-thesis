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
    
    # Natural Earth direct download URL
    url = "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip"
    zip_path = "data/ne_10m_admin_0_countries.zip"
    extract_dir = "data/natural_earth"
    
    # Create directories
    Path("data").mkdir(exist_ok=True)
    Path(extract_dir).mkdir(exist_ok=True)
    
    # Download if not exists
    if not os.path.exists(zip_path):
        print(f"  Downloading from {url}...")
        urllib.request.urlretrieve(url, zip_path)
        print(f"  ✓ Downloaded {os.path.getsize(zip_path) / (1024**2):.2f} MB")
    else:
        print(f"  ✓ Using cached download")
    
    # Extract
    print("  Extracting shapefile...")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_dir)
    
    # Load and process
    print("  Processing data...")
    countries = gpd.read_file(f"{extract_dir}/ne_10m_admin_0_countries.shp")
    
    # Keep only columns that exist (some may have changed names)
    # Essential columns: NAME, POP_EST, CONTINENT, geometry
    # GDP_MD_EST might be missing – we drop it
    available_cols = countries.columns.tolist()
    cols_to_keep = ['NAME', 'POP_EST', 'CONTINENT', 'geometry']
    # Only keep columns that actually exist
    cols_present = [col for col in cols_to_keep if col in available_cols]
    countries = countries[cols_present]
    
    # Explode multipolygons to separate features (increases complexity)
    countries = countries.explode(index_parts=True).reset_index(drop=True)
    
    # Save to GeoPackage
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
    
    # Create realistic distribution:
    # 40% clustered in Northern Hemisphere populated regions
    # 30% distributed globally
    # 20% concentrated near coastlines
    # 10% in Southern Hemisphere populated regions
    
    points_data = []
    
    # Northern Hemisphere cities (40%)
    n_nh = int(n_points * 0.40)
    nh_centers = [
        (40.7128, -74.0060),   # New York
        (51.5074, -0.1278),    # London
        (35.6762, 139.6503),   # Tokyo
        (28.6139, 77.2090),    # Delhi
        (31.2304, 121.4737),   # Shanghai
    ]
    for lat_c, lon_c in nh_centers:
        n_cluster = n_nh // len(nh_centers)
        lats = np.random.normal(lat_c, 2.0, n_cluster)
        lons = np.random.normal(lon_c, 2.0, n_cluster)
        points_data.extend(list(zip(lats, lons)))
    
    # Global uniform (30%)
    n_global = int(n_points * 0.30)
    lats_global = np.random.uniform(-90, 90, n_global)
    lons_global = np.random.uniform(-180, 180, n_global)
    points_data.extend(list(zip(lats_global, lons_global)))
    
    # Coastal regions (20%)
    n_coastal = int(n_points * 0.20)
    coastal_lats = np.concatenate([
        np.random.normal(0, 20, n_coastal // 3),     # Equatorial
        np.random.normal(45, 10, n_coastal // 3),    # Mid-latitude N
        np.random.normal(-35, 10, n_coastal // 3),   # Mid-latitude S
    ])
    coastal_lons = np.random.uniform(-180, 180, n_coastal)
    points_data.extend(list(zip(coastal_lats, coastal_lons)))
    
    # Southern Hemisphere cities (10%)
    n_sh = int(n_points * 0.10)
    sh_centers = [
        (-33.8688, 151.2093),  # Sydney
        (-23.5505, -46.6333),  # São Paulo
        (-26.2041, 28.0473),   # Johannesburg
    ]
    for lat_c, lon_c in sh_centers:
        n_cluster = n_sh // len(sh_centers)
        lats = np.random.normal(lat_c, 2.0, n_cluster)
        lons = np.random.normal(lon_c, 2.0, n_cluster)
        points_data.extend(list(zip(lats, lons)))
    
    # Convert to DataFrame
    df = pd.DataFrame(points_data[:n_points], columns=['lat', 'lon'])
    
    # Clip to valid ranges
    df['lat'] = df['lat'].clip(-90, 90)
    df['lon'] = df['lon'].clip(-180, 180)
    
    # Add synthetic attributes
    df['device_id'] = np.random.randint(1, 10000, n_points)
    df['timestamp'] = pd.date_range('2024-01-01', periods=n_points, freq='s')
    df['accuracy_m'] = np.random.exponential(10, n_points).clip(1, 100)
    
    # Save
    output_path = "data/gps_points_1m.csv"
    df.to_csv(output_path, index=False)
    
    # Calculate checksum for validation
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
    
    # Create data directory
    Path("data").mkdir(exist_ok=True)
    
    # Generate datasets
    countries = download_natural_earth()
    points = generate_gps_points()
    
    # Summary
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
