#!/usr/bin/env python3
"""
SCENARIO E: Raster Algebra & Band Math - Python Implementation
"""
from pathlib import Path

import argparse
import os
import sys
import time
import json
import hashlib

import numpy as np
import tracemalloc

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

def load_cuprite_bands(data_mode):
    """Load Cuprite hyperspectral data as separate bands."""
    # Synthetic mode: skip real data check
    if data_mode == "synthetic":
        shape = (512, 614)
        np.random.seed(42)
        return {
            "green": np.random.rand(*shape).astype(np.float32) * 1000,
            "red":   np.random.rand(*shape).astype(np.float32) * 800,
            "nir":   np.random.rand(*shape).astype(np.float32) * 2000,
            "swir":  np.random.rand(*shape).astype(np.float32) * 1500,
            "shape": (4, *shape),
        }, "synthetic"

    # Try real Cuprite data
    try:
        import scipy.io as sio
        mat_path = str(DATA_DIR / "Cuprite.mat")
        if os.path.exists(mat_path):
            mat_data = sio.loadmat(mat_path)
            data_key = [k for k in mat_data.keys() if not k.startswith("__")][0]
            data = mat_data[data_key]
            if data.shape[2] == 224:
                data = np.transpose(data, (2, 0, 1))
            elif data.shape[0] == 224:
                pass
            elif data.shape[1] == 224 and data.shape[2] == 614:
                data = np.transpose(data, (2, 0, 1))
                data = np.transpose(data, (2, 0, 1))
            band_560 = data[30, :, :].astype(np.float32)
            band_670 = data[50, :, :].astype(np.float32)
            band_780 = data[70, :, :].astype(np.float32)
            band_900 = data[90, :, :].astype(np.float32)
            rows, cols = band_560.shape
            print(f"  ✓ Loaded real Cuprite data: {data.shape}")
            return {
                "green": band_560, "red": band_670, "nir": band_780, "swir": band_900,
                "shape": (4, rows, cols),
            }, "real"
    except Exception as e:
        print(f"Warning: Could not load Cuprite data: {e}")
        if data_mode == "real":
            print("  x Real data required but unavailable")
            sys.exit(1)
        print("  → Using synthetic data instead...")

    # Fallback synthetic
    shape = (512, 614)
    np.random.seed(42)
    return {
        "green": np.random.rand(*shape).astype(np.float32) * 1000,
        "red":   np.random.rand(*shape).astype(np.float32) * 800,
        "nir":   np.random.rand(*shape).astype(np.float32) * 2000,
        "swir":  np.random.rand(*shape).astype(np.float32) * 1500,
        "shape": (4, *shape),
    }, "synthetic"

def benchmark_ndvi(nir, red):
    numerator = nir - red
    denominator = nir + red
    with np.errstate(divide="ignore", invalid="ignore"):
        ndvi = np.where(denominator != 0, numerator / denominator, 0)
    return ndvi

def benchmark_band_arithmetic(green, red, nir, swir):
    results = {}
    results["sum"] = green + red + nir + swir
    results["difference"] = nir - red
    results["ratio"] = np.where(red != 0, nir / red, 0)
    blue = green * 0.8
    results["evi"] = 2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1)
    L = 0.5
    results["savi"] = ((nir - red) / (nir + red + L)) * (1 + L)
    results["ndwi"] = (green - nir) / (green + nir)
    results["nbr"] = (nir - swir) / (nir + swir)
    return results

def benchmark_convolution_3x3(data):
    from scipy.ndimage import uniform_filter
    return uniform_filter(data, size=3, mode="constant")

def run_raster_algebra_benchmark(data_mode="auto"):
    print("=" * 70)
    print("PYTHON - Scenario E: Raster Algebra & Band Math")
    print("=" * 70)
    print("\n[1/4] Loading hyperspectral data...")
    bands, data_source = load_cuprite_bands(data_mode)
    print(f"  ✓ Loaded {bands['shape'][0]} bands, shape: {bands['shape'][1:]}")
    results = {}
    all_hashes = []
    print("\n[2/4] Testing NDVI calculation...")
    tracemalloc.start()
    def ndvi_task(): return benchmark_ndvi(bands["nir"], bands["red"])
    times, peak, _ = run_benchmark(ndvi_task, runs=10, warmup=2)
    ndvi_result = ndvi_task()
    ndvi_hash = generate_hash(ndvi_result)
    all_hashes.append(ndvi_hash)
    print(f"  ✓ Min: {min(times):.4f}s")
    results["ndvi"] = {"min_time_s": min(times), "mean_time_s": np.mean(times), "std_time_s": np.std(times, ddof=1), "median_time_s": float(np.median(times)), "max_time_s": max(times), "times": times, "validation_hash": ndvi_hash}
    print("\n[3/4] Testing band arithmetic...")
    def band_math_task(): return benchmark_band_arithmetic(bands["green"], bands["red"], bands["nir"], bands["swir"])
    times, peak, _ = run_benchmark(band_math_task, runs=10, warmup=2)
    indices_result = band_math_task()
    indices_hash = generate_hash(list(indices_result.values()))
    all_hashes.append(indices_hash)
    print(f"  ✓ Min: {min(times):.4f}s")
    results["band_arithmetic"] = {"min_time_s": min(times), "mean_time_s": np.mean(times), "std_time_s": np.std(times, ddof=1), "median_time_s": float(np.median(times)), "max_time_s": max(times), "times": times, "validation_hash": indices_hash}
    print("\n[4/4] Testing 3x3 convolution filter...")
    def conv_task(): return benchmark_convolution_3x3(bands["nir"])
    times, peak, _ = run_benchmark(conv_task, runs=10, warmup=2)
    conv_result = conv_task()
    conv_hash = generate_hash(conv_result)
    all_hashes.append(conv_hash)
    print(f"  ✓ Min: {min(times):.4f}s")
    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    results["convolution_3x3"] = {"min_time_s": min(times), "mean_time_s": np.mean(times), "std_time_s": np.std(times, ddof=1), "median_time_s": float(np.median(times)), "max_time_s": max(times), "times": times, "peak_memory_mb": peak / 1024 / 1024, "validation_hash": conv_hash}
    OUTPUT_DIR.mkdir(exist_ok=True)
    RESULTS_DIR.mkdir(exist_ok=True)
    output_data = {"language": "python", "scenario": "raster_algebra", "data_source": data_source, "data_description": "Cuprite.mat" if data_source == "real" else "synthetic 4×512×614", "data_shape": list(bands["shape"]), "results": results, "all_hashes": all_hashes, "combined_hash": generate_hash(all_hashes)}
    with open(OUTPUT_DIR / "raster_algebra_python_results.json", "w") as f: json.dump(output_data, f, indent=2)
    print(f"✓ Results saved")
    return output_data

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Raster Algebra Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    args = parser.parse_args()
    run_raster_algebra_benchmark(data_mode=args.data)
