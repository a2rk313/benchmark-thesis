#!/usr/bin/env python3
"""
SCENARIO C: Spatial Interpolation - Python Implementation
Task: Inverse Distance Weighting (IDW) interpolation on scattered points
Dataset: 50,000 points from shared CSV or synthetic fallback
Metrics: Computational throughput, numerical efficiency, vectorization
"""
from pathlib import Path

import argparse
import numpy as np
import pandas as pd
import json
import hashlib
import sys
import time
import os

from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import generate_hash

PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
OUTPUT_DIR = Path(__file__).parent.parent / "results"
VALIDATION_DIR = Path(__file__).parent.parent / "validation"

RUNS = 5
WARMUP = 2


def generate_synthetic_idw_points(n_points=50000):
    """Generate synthetic IDW input points matching shared CSV format."""
    np.random.seed(42)
    x = np.random.uniform(0, 1000, n_points)
    y = np.random.uniform(0, 1000, n_points)
    values = 100 * np.sin(x / 200 + 10) * np.cos(y / 200) + 50 * np.sin(x / 50) + 20 * np.random.randn(n_points)
    return x, y, values


def load_idw_data(data_mode):
    """Load IDW data based on mode: auto (real→synthetic), real, or synthetic."""
    csv_path = DATA_DIR / "synthetic" / "idw_points_50k.csv"

    if data_mode == "synthetic":
        x, y, values = generate_synthetic_idw_points()
        return x, y, values, "synthetic"

    if os.path.exists(csv_path) or data_mode == "real":
        try:
            df = pd.read_csv(csv_path)
            print(f"  ✓ Loaded {len(df):,} points from shared CSV")
            return df["x"].values, df["y"].values, df["value"].values, "real"
        except Exception as e:
            if data_mode == "real":
                print(f"  x Real data load failed: {e}")
                sys.exit(1)
            print(f"  - CSV unavailable ({e}), using synthetic")

    x, y, values = generate_synthetic_idw_points()
    return x, y, values, "synthetic"


def idw_interpolation(points, values, grid_x, grid_y, power=2, neighbors=12):
    tree = cKDTree(points)
    grid_points = np.column_stack([grid_x.ravel(), grid_y.ravel()])
    distances, indices = tree.query(grid_points, k=neighbors)
    distances = np.maximum(distances, 1e-10)
    weights = 1.0 / (distances ** power)
    weights /= weights.sum(axis=1, keepdims=True)
    interpolated = (weights * values[indices]).sum(axis=1)
    return interpolated.reshape(grid_x.shape)


def main():
    parser = argparse.ArgumentParser(description="IDW Interpolation Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    args = parser.parse_args()

    print("=" * 70)
    print("PYTHON - Scenario C: Spatial Interpolation (IDW)")
    print("=" * 70)

    print("\n[1/4] Loading scattered point data...")
    x, y, values, data_source = load_idw_data(args.data)
    n_points = len(values)
    points = np.column_stack([x, y])
    print(f"  ✓ Loaded {n_points:,} scattered points ({data_source})")
    print(f"  ✓ Value range: [{values.min():.2f}, {values.max():.2f}]")

    print("\n[2/4] Creating interpolation grid...")
    grid_resolution = 1000
    grid_x, grid_y = np.meshgrid(
        np.linspace(0, 1000, grid_resolution),
        np.linspace(0, 1000, grid_resolution)
    )
    print(f"  ✓ Grid size: {grid_resolution} × {grid_resolution}")
    print(f"  ✓ Total interpolation points: {grid_resolution**2:,}")

    print("\n[3/4] Performing IDW interpolation ({} runs, {} warmup)...".format(RUNS, WARMUP))

    def task():
        return idw_interpolation(points, values, grid_x, grid_y, power=2, neighbors=12)

    for _ in range(WARMUP):
        task()

    times = []
    interpolated = None
    for _ in range(RUNS):
        t_start = time.perf_counter()
        interpolated = task()
        t_end = time.perf_counter()
        times.append(t_end - t_start)

    points_per_second = (grid_resolution ** 2) / min(times)
    print(f"  ✓ Min: {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")
    print(f"  ✓ Processing rate: {points_per_second:,.0f} grid points/second")

    print("\n[4/4] Computing metrics and validation...")
    mean_value = float(np.mean(interpolated))
    std_value = float(np.std(interpolated))
    median_value = float(np.median(interpolated))
    print(f"  ✓ Mean interpolated value: {mean_value:.2f}")
    print(f"  ✓ Std dev: {std_value:.2f}")

    result_hash = generate_hash(interpolated.ravel())
    print(f"  ✓ Validation hash: {result_hash}")

    results = {
        "language": "python",
        "scenario": "interpolation_idw",
        "data_source": data_source,
        "data_description": "idw_points_50k.csv" if data_source == "real" else "synthetic 50K points (seed 42)",
        "n_points": n_points,
        "grid_size": grid_resolution,
        "total_interpolated": grid_resolution ** 2,
        "min_time_s": min(times),
        "mean_time_s": float(np.mean(times)),
        "std_time_s": float(np.std(times, ddof=1)),
        "median_time_s": float(np.median(times)),
        "max_time_s": max(times),
        "times": times,
        "points_per_second": points_per_second,
        "mean_value": mean_value,
        "std_value": std_value,
        "median_value": median_value,
        "validation_hash": result_hash
    }

    OUTPUT_DIR.mkdir(exist_ok=True)
    VALIDATION_DIR.mkdir(exist_ok=True)
    with open(OUTPUT_DIR / "interpolation_idw_python.json", "w") as f:
        json.dump(results, f, indent=2)
    with open(VALIDATION_DIR / "interpolation_python_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("✓ Results saved")
    print("=" * 70)


if __name__ == "__main__":
    main()
