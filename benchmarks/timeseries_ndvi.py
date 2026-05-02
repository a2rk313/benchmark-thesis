#!/usr/bin/env python3
"""
SCENARIO E: NDVI Time-Series - Python Implementation
Tests: Temporal aggregation, trend analysis (OLS), and multi-band processing
Dataset: Synthetic NDVI stack (46 dates × 1200 × 1200) or real MODIS HDF
"""
from pathlib import Path

import argparse
import numpy as np
import time
import json
import hashlib
import os
import sys

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import generate_hash

PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
OUTPUT_DIR = Path(__file__).parent.parent / "results"
VALIDATION_DIR = Path(__file__).parent.parent / "validation"

RUNS = 10
WARMUP = 2


def load_real_modis_ndvi():
    """Load NDVI from real MODIS HDF if available."""
    modis_dir = DATA_DIR / "modis"
    bin_path = modis_dir / "modis_ndvi_timeseries.bin"
    hdr_path = modis_dir / "modis_ndvi_timeseries.hdr"

    if bin_path.exists() and hdr_path.exists():
        try:
            with open(hdr_path) as f:
                for line in f:
                    if line.startswith("samples"):
                        n_cols = int(line.split("=")[1].strip())
                    elif line.startswith("lines"):
                        n_rows = int(line.split("=")[1].strip())
                    elif line.startswith("bands"):
                        n_bands = int(line.split("=")[1].strip())

            data = np.fromfile(bin_path, dtype=np.float32)
            data = data.reshape(n_bands, n_rows, n_cols)
            print(f"  ✓ Loaded real MODIS NDVI: {n_bands} × {n_rows} × {n_cols}")
            return data
        except Exception as e:
            print(f"  ⚠ Failed to load real MODIS data: {e}")
    return None


def generate_synthetic_ndvi_stack(n_dates=46, height=1200, width=1200):
    np.random.seed(42)
    x = np.linspace(-1, 1, width)
    y = np.linspace(-1, 1, height)
    xx, yy = np.meshgrid(x, y)
    base_vegetation = 0.5 * (1 - (xx**2 + yy**2))
    red_bands = np.zeros((n_dates, height, width), dtype=np.float32)
    nir_bands = np.zeros((n_dates, height, width), dtype=np.float32)
    for t in range(n_dates):
        vegetation_level = 0.5 + 0.3 * np.sin(2 * np.pi * t / n_dates)
        red_noise = np.random.normal(0, 0.05, (height, width))
        nir_noise = np.random.normal(0, 0.05, (height, width))
        red_bands[t] = (0.1 + 0.2 * (1 - base_vegetation * vegetation_level) + red_noise).astype(np.float32)
        nir_bands[t] = (0.3 + 0.5 * base_vegetation * vegetation_level + nir_noise).astype(np.float32)
    epsilon = 1e-6
    ndvi_stack = ((nir_bands - red_bands) / (nir_bands + red_bands + epsilon)).astype(np.float32)
    ndvi_stack = np.clip(ndvi_stack, -0.1, 1.0)
    return ndvi_stack


def load_ndvi_data(data_mode):
    """Load NDVI data based on mode: auto (real→synthetic), real, or synthetic."""
    if data_mode == "synthetic":
        ndvi_stack = generate_synthetic_ndvi_stack()
        return ndvi_stack, "synthetic"

    data = load_real_modis_ndvi()
    if data is not None:
        return data, "real"

    if data_mode == "real":
        print("  x Real MODIS data not available")
        sys.exit(1)

    print("  → Using synthetic NDVI stack")
    ndvi_stack = generate_synthetic_ndvi_stack()
    return ndvi_stack, "synthetic"


def calculate_ndvi_statistics(ndvi_stack):
    n_dates, height, width = ndvi_stack.shape
    mean_ndvi = np.mean(ndvi_stack, axis=0)
    max_ndvi = np.max(ndvi_stack, axis=0)
    min_ndvi = np.min(ndvi_stack, axis=0)
    time_index = np.arange(n_dates).astype(np.float32)
    mean_time = np.mean(time_index)
    denominator = np.sum((time_index - mean_time)**2)
    numerator = np.sum((time_index[:, None, None] - mean_time) * (ndvi_stack - mean_ndvi), axis=0)
    ndvi_trend = numerator / denominator
    growing_season = np.sum(ndvi_stack > 0.3, axis=0)
    amplitude = max_ndvi - min_ndvi
    return mean_ndvi, ndvi_trend, amplitude, growing_season


def main():
    parser = argparse.ArgumentParser(description="NDVI Time-Series Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    args = parser.parse_args()

    print("=" * 70)
    print("PYTHON - Scenario E: NDVI Time-Series")
    print("=" * 70)

    print("\n[1/4] Loading NDVI stack...")
    ndvi_stack, data_source = load_ndvi_data(args.data)
    n_dates, height, width = ndvi_stack.shape
    print(f"  ✓ Stack shape: {n_dates} dates × {height} × {width} pixels")

    print("\n[2/4] Running NDVI time-series analysis ({} runs, {} warmup)...".format(RUNS, WARMUP))

    def task():
        return calculate_ndvi_statistics(ndvi_stack)

    for _ in range(WARMUP):
        task()

    times = []
    result = None
    for _ in range(RUNS):
        t_start = time.perf_counter()
        result = task()
        t_end = time.perf_counter()
        times.append(t_end - t_start)

    mean_ndvi, ndvi_trend, amplitude, growing_season = result

    print(f"  ✓ Min: {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")

    print("\n[3/4] Computing domain statistics...")
    mean_ndvi_val = float(np.mean(mean_ndvi))
    trend_val = float(np.mean(ndvi_trend))
    amplitude_val = float(np.mean(amplitude))
    growing_days = float(np.mean(growing_season))
    print(f"  ✓ Mean NDVI: {mean_ndvi_val:.4f}")
    print(f"  ✓ Mean trend: {trend_val:.6f}")
    print(f"  ✓ Mean amplitude: {amplitude_val:.4f}")
    print(f"  ✓ Avg growing season: {growing_days:.1f} dates")

    print("\n[4/4] Validation and export...")
    hash_arrays = [mean_ndvi.ravel(), ndvi_trend.ravel(), amplitude.ravel()]
    result_hash = generate_hash(hash_arrays)
    print(f"  ✓ Validation hash: {result_hash}")

    output = {
        "language": "python",
        "scenario": "timeseries_ndvi",
        "data_source": data_source,
        "data_description": "MODIS HDF" if data_source == "real" else f"synthetic {n_dates}×{height}×{width}",
        "n_dates": n_dates,
        "min_time_s": min(times),
        "mean_time_s": float(np.mean(times)),
        "std_time_s": float(np.std(times, ddof=1)),
        "median_time_s": float(np.median(times)),
        "max_time_s": max(times),
        "times": times,
        "mean_ndvi": mean_ndvi_val,
        "mean_trend": trend_val,
        "mean_amplitude": amplitude_val,
        "avg_growing_season": growing_days,
        "hash": result_hash,
        "validation_hash": result_hash,
    }

    OUTPUT_DIR.mkdir(exist_ok=True)
    VALIDATION_DIR.mkdir(exist_ok=True)
    with open(OUTPUT_DIR / "timeseries_ndvi_python.json", "w") as f:
        json.dump(output, f, indent=2)
    with open(VALIDATION_DIR / "timeseries_python_results.json", "w") as f:
        json.dump(output, f, indent=2)
    print("✓ Results saved")


if __name__ == "__main__":
    main()
