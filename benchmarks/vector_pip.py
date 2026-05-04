#!/usr/bin/env python3
"""
SCENARIO B: Complex Vector Operations - Python Implementation
Task: Point-in-Polygon spatial join + Haversine distance calculation
Dataset: 1M GPS points × Natural Earth countries (high-vertex complexity)
Metrics: Computational throughput, GEOS interface efficiency

FAIRNESS NOTES (vs R/Julia):
  1. gpd.sjoin() rebuilds its STRtree on every call — index construction is
     included in timing, consistent with R (terra::extract) and Julia
     (STRtree now built inside run_pip_and_distances).
  2. gc.collect() called before timing loop — consistent with R (gc()) and
     Julia (GC.gc()).
  3. GEOS/GDAL use all available cores by default — consistent with Julia
     (Threads.@threads --threads auto) and R (terra default).
"""
import gc
import os
import warnings

from pathlib import Path

import argparse
import geopandas as gpd
import pandas as pd
import numpy as np
import shapely
import sys
import json
import time

from shapely.geometry import box

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import generate_hash

PROJECT_ROOT   = Path(__file__).parent.parent
DATA_DIR       = PROJECT_ROOT / "data"
OUTPUT_DIR     = PROJECT_ROOT / "results"
VALIDATION_DIR = PROJECT_ROOT / "validation"

RUNS   = 10
WARMUP = 2


def load_synthetic_polys(n_countries=50):
    np.random.seed(42)
    geometries, names = [], []
    lat_step = 180 / (n_countries // 2 + 1)
    lon_step = 360 / (n_countries // 2 + 1)
    idx = 0
    for i in range(n_countries // 2 + 1):
        for j in range(n_countries // 2 + 1):
            if idx >= n_countries:
                break
            min_lon = -180 + j * lon_step + np.random.uniform(-2, 2)
            max_lon = min_lon + lon_step + np.random.uniform(-2, 2)
            min_lat = -90  + i * lat_step + np.random.uniform(-2, 2)
            max_lat = min_lat + lat_step + np.random.uniform(-2, 2)
            min_lon, max_lon = max(-180, min_lon), min(180, max_lon)
            min_lat, max_lat = max(-90,  min_lat), min(90,  max_lat)
            if max_lon > min_lon and max_lat > min_lat:
                geometries.append(box(min_lon, min_lat, max_lon, max_lat))
                names.append(f"Country_{idx + 1}")
                idx += 1
    return gpd.GeoDataFrame({"name": names}, geometry=geometries, crs="EPSG:4326")


def load_synthetic_points(n_points=1_000_000):
    np.random.seed(42)
    lats = np.random.uniform(-90,  90,  n_points)
    lons = np.random.uniform(-180, 180, n_points)
    return pd.DataFrame({"lat": lats, "lon": lons})


def load_data(data_mode):
    if data_mode == "synthetic":
        polys     = load_synthetic_polys()
        points_df = load_synthetic_points()
        points    = gpd.GeoDataFrame(
            points_df,
            geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]),
            crs="EPSG:4326",
        )
        print(f"  + Synthetic: {len(polys)} polygons, {len(points)} points")
        return polys, points, "synthetic"

    gpkg     = DATA_DIR / "natural_earth_countries.gpkg"
    csv_path = DATA_DIR / "gps_points_1m.csv"
    if (gpkg.exists() and csv_path.exists()) or data_mode == "real":
        try:
            print(f"  Loading polygons: {gpkg}")
            polys     = gpd.read_file(str(gpkg))
            print(f"  Loading points:  {csv_path}")
            points_df = pd.read_csv(str(csv_path))
            points    = gpd.GeoDataFrame(
                points_df,
                geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]),
                crs="EPSG:4326",
            )
            print(f"  + Real: {len(polys)} polygons, {len(points)} points")
            return polys, points, "real"
        except Exception as e:
            if data_mode == "real":
                print(f"  x Real data load failed: {e}")
                sys.exit(1)
            print(f"  - Real data unavailable ({e}), using synthetic")

    polys     = load_synthetic_polys()
    points_df = load_synthetic_points()
    points    = gpd.GeoDataFrame(
        points_df,
        geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]),
        crs="EPSG:4326",
    )
    print(f"  + Synthetic: {len(polys)} polygons, {len(points)} points")
    return polys, points, "synthetic"


def haversine_vectorized(lat1, lon1, lat2, lon2):
    R    = 6371000.0
    dlat = np.radians(lat2 - lat1)
    dlon = np.radians(lon2 - lon1)
    a    = (
        np.sin(dlat / 2.0) ** 2
        + np.cos(np.radians(lat1)) * np.cos(np.radians(lat2)) * np.sin(dlon / 2.0) ** 2
    )
    return R * 2 * np.arctan2(np.sqrt(a), np.sqrt(1 - a))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", choices=["auto", "real", "synthetic"], default="auto")
    args = parser.parse_args()

    print("=" * 70)
    print("PYTHON - Scenario B: Vector Point-in-Polygon + Haversine")
    print("=" * 70)

    print("\n[1/4] Loading data...")
    polys, points, data_source = load_data(args.data)

    # Precompute centroid coordinates as plain numpy arrays once, outside the
    # timed loop — consistent with R (crds(centroids())) and Julia (c_lons/c_lats).
    # Suppress the geographic-CRS warning: all three implementations compute
    # centroids in EPSG:4326 for consistency, so the slight inaccuracy is equal
    # across languages and irrelevant to the benchmark.
    print("  Precomputing polygon centroids...")
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Geometry is in a geographic CRS")
        centroid_lons = polys.geometry.centroid.x.values
        centroid_lats = polys.geometry.centroid.y.values
    print(f"  ✓ Precomputed {len(polys)} polygon centroids")

    print("\n[2/4] Running spatial join + Haversine ({} runs, {} warmup)...".format(
        RUNS, WARMUP))

    # FAIRNESS: gpd.sjoin rebuilds its STRtree on every call — index
    # construction is included in timing, consistent with R and Julia.
    # No lsuffix/rsuffix: there is no column name collision between the points
    # and polys GeoDataFrames, so suffixes are unnecessary. Without rsuffix,
    # the right-index column is always named "index_right" across GeoPandas
    # versions — passing rsuffix renames it to "index_right{rsuffix}" in
    # newer releases, which caused a KeyError.
    def task():
        joined = gpd.sjoin(points, polys, how="inner", predicate="within")

        # Vectorized coordinate access — no Python-level loop over geometry objects.
        point_lats = joined.geometry.y.values
        point_lons = joined.geometry.x.values

        # Index into pre-built numpy arrays — no centroid recomputation.
        poly_idx = joined["index_right"].values
        c_lats   = centroid_lats[poly_idx]
        c_lons   = centroid_lons[poly_idx]

        distances = haversine_vectorized(point_lats, point_lons, c_lats, c_lons)
        return joined, distances

    for _ in range(WARMUP):
        task()

    # FAIRNESS: force GC before timing loop — consistent with R (gc()) and
    # Julia (GC.gc()).
    gc.collect()

    times     = []
    joined    = None
    distances = None
    for _ in range(RUNS):
        t0 = time.perf_counter()
        joined, distances = task()
        times.append(time.perf_counter() - t0)

    total_distance  = float(np.sum(distances))
    mean_distance   = float(np.mean(distances))
    median_distance = float(np.median(distances))
    max_distance    = float(np.max(distances))

    print(f"  ✓ Min:  {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")
    print(f"  ✓ Matched {len(joined)} points to polygons")
    print(f"  ✓ Match rate: {100 * len(joined) / len(points):.2f}%")
    print(f"  ✓ Total distance: {total_distance:,.0f} m")
    print(f"  ✓ Mean distance:  {mean_distance:,.0f} m")

    print("\n[3/4] Validation...")
    result_hash = generate_hash(distances)
    print(f"  ✓ Validation hash: {result_hash}")

    print("\n[4/4] Export...")
    results = {
        "language":        "python",
        "scenario":        "vector_pip",
        "data_source":     data_source,
        "data_description": (
            "natural_earth_countries.gpkg + gps_points_1m.csv"
            if data_source == "real" else "synthetic"
        ),
        "n_points":          int(len(points)),
        "n_polygons":        int(len(polys)),
        "matches_found":     int(len(joined)),
        "total_distance_m":  total_distance,
        "mean_distance_m":   mean_distance,
        "median_distance_m": median_distance,
        "max_distance_m":    max_distance,
        "min_time_s":        min(times),
        "mean_time_s":       float(np.mean(times)),
        "std_time_s":        float(np.std(times, ddof=1)),
        "median_time_s":     float(np.median(times)),
        "max_time_s":        max(times),
        "times":             times,
        "validation_hash":   result_hash,
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
