#!/usr/bin/env python3
"""
SCENARIO B: Complex Vector Operations - Python Implementation
Task: Point-in-Polygon spatial join + Haversine distance calculation
Dataset: 1M GPS points × Natural Earth countries (high-vertex complexity)
Metrics: Computational throughput, GEOS interface efficiency
"""
from pathlib import Path

import argparse
import geopandas as gpd
import pandas as pd
import numpy as np
import shapely
import sys
import json
import hashlib
import time

from shapely.geometry import box

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import generate_hash

PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
OUTPUT_DIR = Path(__file__).parent.parent / "results"
VALIDATION_DIR = Path(__file__).parent.parent / "validation"

RUNS = 10
WARMUP = 2


def load_synthetic_polys(n_countries=50):
    """Generate synthetic country-like polygons."""
    np.random.seed(42)
    geometries = []
    names = []
    lat_step = 180 / (n_countries // 2 + 1)
    lon_step = 360 / (n_countries // 2 + 1)
    idx = 0
    for i in range(n_countries // 2 + 1):
        for j in range(n_countries // 2 + 1):
            if idx >= n_countries:
                break
            min_lon = -180 + j * lon_step + np.random.uniform(-2, 2)
            max_lon = min_lon + lon_step + np.random.uniform(-2, 2)
            min_lat = -90 + i * lat_step + np.random.uniform(-2, 2)
            max_lat = min_lat + lat_step + np.random.uniform(-2, 2)
            min_lon, max_lon = max(-180, min_lon), min(180, max_lon)
            min_lat, max_lat = max(-90, min_lat), min(90, max_lat)
            if max_lon > min_lon and max_lat > min_lat:
                geometries.append(box(min_lon, min_lat, max_lon, max_lat))
                names.append(f"Country_{idx + 1}")
                idx += 1
    gdf = gpd.GeoDataFrame({"name": names}, geometry=geometries, crs="EPSG:4326")
    return gdf


def load_synthetic_points(n_points=1_000_000):
    """Generate synthetic GPS-like points."""
    np.random.seed(42)
    lats = np.random.uniform(-90, 90, n_points)
    lons = np.random.uniform(-180, 180, n_points)
    device_ids = np.random.randint(1, 10000, n_points)
    accuracies = np.random.exponential(10, n_points).clip(1, 100)
    return pd.DataFrame({"lat": lats, "lon": lons, "device_id": device_ids, "accuracy_m": accuracies})


def load_data(data_mode):
    """Load vector data based on mode: auto (real→synthetic), real, or synthetic."""
    if data_mode == "synthetic":
        polys = load_synthetic_polys()
        points_df = load_synthetic_points()
        points = gpd.GeoDataFrame(points_df, geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]), crs="EPSG:4326")
        print(f"  + Synthetic: {len(polys)} polygons, {len(points)} points")
        return polys, points, "synthetic"

    gpkg = DATA_DIR / "natural_earth_countries.gpkg"
    csv_path = DATA_DIR / "gps_points_1m.csv"
    if (gpkg.exists() and csv_path.exists()) or data_mode == "real":
        try:
            print(f"  Loading polygons: {gpkg}")
            polys = gpd.read_file(str(gpkg))
            print(f"  Loading points: {csv_path}")
            points_df = pd.read_csv(str(csv_path))
            points = gpd.GeoDataFrame(points_df, geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]), crs="EPSG:4326")
            print(f"  + Real: {len(polys)} polygons, {len(points)} points")
            return polys, points, "real"
        except Exception as e:
            if data_mode == "real":
                print(f"  x Real data load failed: {e}")
                sys.exit(1)
            print(f"  - Real data unavailable ({e}), using synthetic")

    polys = load_synthetic_polys()
    points_df = load_synthetic_points()
    points = gpd.GeoDataFrame(points_df, geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]), crs="EPSG:4326")
    print(f"  + Synthetic: {len(polys)} polygons, {len(points)} points")
    return polys, points, "synthetic"


def haversine_vectorized(lat1, lon1, lat2, lon2):
    R = 6371000.0
    lat1_rad = np.radians(lat1)
    lat2_rad = np.radians(lat2)
    dlat = np.radians(lat2 - lat1)
    dlon = np.radians(lon2 - lon1)
    a = (
        np.sin(dlat / 2.0) ** 2
        + np.cos(lat1_rad) * np.cos(lat2_rad) * np.sin(dlon / 2.0) ** 2
    )
    c = 2 * np.arctan2(np.sqrt(a), np.sqrt(1 - a))
    return R * c


def main():
    parser = argparse.ArgumentParser(description="Vector Point-in-Polygon Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    args = parser.parse_args()

    print("=" * 70)
    print("PYTHON - Scenario B: Vector Point-in-Polygon + Haversine")
    print("=" * 70)

    print("\n[1/4] Loading data...")
    polys, points, data_source = load_data(args.data)

    polys_sindex = polys.sindex

    print("\n[2/4] Running spatial join + Haversine ({} runs, {} warmup)...".format(RUNS, WARMUP))

    def task():
        joined = gpd.sjoin(points, polys, how="inner", predicate="within",
                          lsuffix='_point', rsuffix='_poly')
        point_coords = np.array([(p.y, p.x) for p in joined.geometry])
        poly_indices = joined["index_right"].values
        centroids = polys.iloc[poly_indices].geometry.centroid
        centroid_coords = np.array([(c.y, c.x) for c in centroids])
        distances = haversine_vectorized(
            point_coords[:, 0], point_coords[:, 1],
            centroid_coords[:, 0], centroid_coords[:, 1],
        )
        return joined, distances

    for _ in range(WARMUP):
        task()

    times = []
    joined = None
    distances = None
    for _ in range(RUNS):
        t_start = time.perf_counter()
        joined, distances = task()
        t_end = time.perf_counter()
        times.append(t_end - t_start)

    total_distance = float(np.sum(distances))
    mean_distance = float(np.mean(distances))
    median_distance = float(np.median(distances))
    max_distance = float(np.max(distances))

    print(f"  ✓ Min: {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")
    print(f"  ✓ Matched {len(joined)} points to polygons")
    print(f"  ✓ Match rate: {100 * len(joined) / len(points):.2f}%")
    print(f"  ✓ Total distance: {total_distance:,.0f} m")
    print(f"  ✓ Mean distance: {mean_distance:,.0f} m")

    print("\n[3/4] Validation...")
    result_hash = generate_hash(distances)
    print(f"  ✓ Validation hash: {result_hash}")

    print("\n[4/4] Export...")
    results = {
        "language": "python",
        "scenario": "vector_pip",
        "data_source": data_source,
        "data_description": "natural_earth_countries.gpkg + gps_points_1m.csv" if data_source == "real" else "synthetic",
        "n_points": int(len(points)),
        "n_polygons": int(len(polys)),
        "matches_found": int(len(joined)),
        "total_distance_m": total_distance,
        "mean_distance_m": mean_distance,
        "median_distance_m": median_distance,
        "max_distance_m": max_distance,
        "min_time_s": min(times),
        "mean_time_s": float(np.mean(times)),
        "std_time_s": float(np.std(times, ddof=1)),
        "median_time_s": float(np.median(times)),
        "max_time_s": max(times),
        "times": times,
        "validation_hash": result_hash,
    }

    OUTPUT_DIR.mkdir(exist_ok=True)
    VALIDATION_DIR.mkdir(exist_ok=True)
    with open(OUTPUT_DIR / "vector_pip_python.json", "w") as f:
        json.dump(results, f, indent=2)
    with open(VALIDATION_DIR / "vector_python_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("✓ Results saved")
    print("=" * 70)


if __name__ == "__main__":
    main()
