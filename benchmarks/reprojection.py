#!/usr/bin/env python3
"""
SCENARIO G: Coordinate Reprojection - Python Implementation
Tests: EPSG:4326 <-> UTM reprojection performance

Academic rationale:
- Coordinate transformation is essential for GIS
- Tests proj library performance
- Common bottleneck in data processing pipelines
"""
from pathlib import Path

import argparse
import os
import sys
import time
import json
import pandas as pd

import numpy as np
import tracemalloc
from pyproj import Transformer, CRS

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import (

    generate_hash,
    shapiro_wilk_test,
    bootstrap_ci,
    run_benchmark,
)

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"


OUTPUT_DIR = Path("validation")
RESULTS_DIR = Path("results")


def generate_test_points(n_points):
    """Generate random lat/lon points globally distributed."""
    np.random.seed(42)
    lats = np.random.uniform(-90, 90, n_points)
    lons = np.random.uniform(-180, 180, n_points)
    return lats, lons


def load_gps_points(max_points=None):
    """Load lat/lon from real GPS points CSV."""
    csv_path = DATA_DIR / "gps_points_1m.csv"
    if not csv_path.exists():
        return None, None
    df = pd.read_csv(csv_path, usecols=["lat", "lon"])
    if max_points and len(df) > max_points:
        df = df.head(max_points)
    return df["lat"].values, df["lon"].values


def reproject_wgs84_to_utm_batch(lats, lons):
    """Reproject WGS84 to UTM zones."""
    results = {"x": [], "y": [], "zones": []}

    # Group by approximate UTM zone
    for i in range(len(lats)):
        lon = lons[i]
        lat = lats[i]

        # Determine UTM zone
        zone = int((lon + 180) / 6) + 1
        hemisphere = "north" if lat >= 0 else "south"
        epsg = f"326{zone:02d}" if hemisphere == "north" else f"327{zone:02d}"

        transformer = Transformer.from_crs("EPSG:4326", epsg, always_xy=True)
        x, y = transformer.transform(lon, lat)

        results["x"].append(x)
        results["y"].append(y)
        results["zones"].append(zone)

    return results


def reproject_wgs84_to_web_mercator(lats, lons):
    """Reproject to Web Mercator (EPSG:3857)."""
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
    x, y = transformer.transform(lons, lats)
    return {"x": x, "y": y}


def reproject_batch_vectorized(lats, lons, src_epsg, dst_epsg):
    """Batch reprojection using pyproj (vectorized)."""
    transformer = Transformer.from_crs(src_epsg, dst_epsg, always_xy=True)
    x, y = transformer.transform(lons, lats)  # pyproj uses xy order
    return {"x": np.array(x), "y": np.array(y)}


def reproject_with_zone_optimization(lats, lons):
    """Optimized reprojection with zone caching."""
    transformer_cache = {}
    results = {"x": [], "y": [], "zone": []}

    for i in range(len(lats)):
        lon = lons[i]
        lat = lats[i]

        zone = int((lon + 180) / 6) + 1
        hemisphere = "north" if lat >= 0 else "south"
        epsg = f"326{zone:02d}" if hemisphere == "north" else f"327{zone:02d}"

        if epsg not in transformer_cache:
            transformer_cache[epsg] = Transformer.from_crs(
                "EPSG:4326", epsg, always_xy=True
            )

        transformer = transformer_cache[epsg]
        x, y = transformer.transform(lon, lat)

        results["x"].append(x)
        results["y"].append(y)
        results["zone"].append(zone)

    return results


def run_reprojection_benchmark(data_mode="auto", size_flag="default"):
    print("=" * 70)
    print("PYTHON - Scenario G: Coordinate Reprojection")
    print("=" * 70)

    sizes = [1000, 5000, 10000, 50000, 100000, 500000]

    if data_mode != "synthetic":
        gps_lats, gps_lons = load_gps_points()
        has_real = gps_lats is not None
        if has_real:
            print(f"  + Real GPS points loaded: {len(gps_lats):,} points")
        if not has_real and data_mode == "real":
            print("  x Real GPS data not found")
            sys.exit(1)
        if not has_real:
            print("  - Real GPS data not found, using synthetic")
            data_mode = "synthetic"
    else:
        has_real = False

    results = {}
    all_hashes = []
    data_source = "real" if has_real and data_mode != "synthetic" else "synthetic"

    for size in sizes:
        print(f"\n[Testing with {size:,} points]")
        print("-" * 40)

        if has_real and data_mode != "synthetic" and size <= len(gps_lats):
            lats = gps_lats[:size]
            lons = gps_lons[:size]
        else:
            lats, lons = generate_test_points(size)

        lats_np = np.array(lats)
        lons_np = np.array(lons)

        # Web Mercator reprojection
        print("  Web Mercator (EPSG:4326 -> 3857)...")

        # Compute result first for validation
        merc_result = reproject_batch_vectorized(
            lats_np, lons_np, "EPSG:4326", "EPSG:3857"
        )
        merc_hash = generate_hash([merc_result["x"].mean(), merc_result["y"].mean()])

        def mercator_task():
            return reproject_batch_vectorized(
                lats_np, lons_np, "EPSG:4326", "EPSG:3857"
            )

        times, peak, _ = run_benchmark(mercator_task, runs=10, warmup=2)

        p_val, is_norm = shapiro_wilk_test(np.array(times))
        ci_lower, ci_upper = bootstrap_ci(np.array(times))

        print(f"    ✓ Min: {min(times):.4f}s (primary)")
        print(f"    ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")
        print(f"    ✓ Rate: {size / min(times):,.0f} points/sec")
        print(f"    ✓ Hash: {merc_hash}")

        results[f"mercator_{size}"] = {
            "n_points": size,
            "min_time_s": min(times),
            "mean_time_s": np.mean(times),
            "std_time_s": np.std(times, ddof=1),
            "median_time_s": float(np.median(times)),
            "max_time_s": max(times),
            "times": times,
            "points_per_second": int(size / min(times)),
            "normality_p": p_val,
            "is_normal": is_norm,
            "ci_95": [ci_lower, ci_upper],
            "validation_hash": merc_hash,
        }

        # UTM reprojection (zone-optimized)
        print("  UTM (zone-optimized)...")

        # Compute result first for validation
        utm_result = reproject_with_zone_optimization(lats, lons)
        utm_hash = generate_hash([utm_result["x"][:100], utm_result["y"][:100]])

        def utm_task():
            return reproject_with_zone_optimization(lats, lons)

        times, peak, _ = run_benchmark(utm_task, runs=5, warmup=2)

        print(f"    ✓ Min: {min(times):.4f}s (primary)")
        print(f"    ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")
        print(f"    ✓ Rate: {size / min(times):,.0f} points/sec")

        results[f"utm_{size}"] = {
            "n_points": size,
            "min_time_s": min(times),
            "mean_time_s": np.mean(times),
            "std_time_s": np.std(times, ddof=1),
            "median_time_s": float(np.median(times)),
            "max_time_s": max(times),
            "times": times,
            "points_per_second": int(size / min(times)),
            "validation_hash": utm_hash,
        }

        all_hashes.extend([merc_hash, utm_hash])

    # Save results
    print("\n" + "=" * 70)
    print("SAVING RESULTS...")
    print("=" * 70)

    OUTPUT_DIR.mkdir(exist_ok=True)
    RESULTS_DIR.mkdir(exist_ok=True)

    output_data = {
        "language": "python",
        "scenario": "coordinate_reprojection",
        "data_source": data_source,
        "data_description": "gps_points_1m.csv" if data_source == "real" else "synthetic random",
        "results": results,
        "all_hashes": all_hashes,
        "combined_hash": generate_hash(all_hashes),
    }

    # Ensure output directories exist
    import os
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    with open(OUTPUT_DIR / "reprojection_python_results.json", "w") as f:
        json.dump(output_data, f, indent=2, default=str)

    with open(RESULTS_DIR / "reprojection_python.json", "w") as f:
        json.dump(results, f, indent=2)

    print(f"✓ Results saved")
    print(f"✓ Combined validation hash: {output_data['combined_hash']}")

    # Scaling analysis
    print("\n[Scaling Analysis]")
    merc_times = [results[f"mercator_{s}"]["min_time_s"] for s in sizes]
    merc_rates = [results[f"mercator_{s}"]["points_per_second"] for s in sizes]

    print(f"  Mercator scaling:")
    for i, size in enumerate(sizes):
        print(f"    {size:>10,}: {merc_times[i]:.4f}s ({merc_rates[i]:>10,} pts/s)")

    print("\n" + "=" * 70)
    print("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    print("=" * 70)

    return output_data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Coordinate Reprojection Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    parser.add_argument("--size", choices=["default", "large"],
                       default="default", help="Size flag for future scaling")
    args = parser.parse_args()
    run_reprojection_benchmark(data_mode=args.data, size_flag=args.size)
