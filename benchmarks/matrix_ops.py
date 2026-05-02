#!/usr/bin/env python3
"""
==================================================================================
Matrix Operations Benchmark - Python Implementation (Standardized)
==================================================================================
Reproduces Tedesco et al. (2025) matrix operation benchmarks
Tasks: Creation/Transpose/Reshape, Power, Sorting, Cross-product, Determinant
==================================================================================
"""
from pathlib import Path

import argparse
import numpy as np
import json
import time
import hashlib

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
VALIDATION_DIR = PROJECT_ROOT / "validation"




def make_rng(data_mode):
    """Create a seeded RNG for reproducible synthetic matrices."""
    seed = 42
    return np.random.default_rng(seed)


def benchmark_matrix_creation_transpose_reshape(n=2500, rng=None):
    if rng is None:
        rng = np.random
    start = time.perf_counter()
    A = rng.standard_normal((n, n))
    A = A.T
    new_rows = int(n * 2 / 5)
    new_cols = int(n * n / new_rows)
    A = A.reshape(new_rows, new_cols)
    A = A.T
    return time.perf_counter() - start

def benchmark_matrix_power(n=2500, rng=None):
    if rng is None:
        rng = np.random
    A = rng.standard_normal((n, n))
    A = np.abs(A) / 2.0
    start = time.perf_counter()
    A_pow = np.power(A, 10)
    return time.perf_counter() - start

def benchmark_sorting(n=1000000, rng=None):
    if rng is None:
        rng = np.random
    arr = rng.standard_normal(n)
    start = time.perf_counter()
    np.sort(arr)
    return time.perf_counter() - start

def benchmark_crossproduct(n=2500, rng=None):
    if rng is None:
        rng = np.random
    A = rng.standard_normal((n, n))
    start = time.perf_counter()
    B = A.T @ A
    return time.perf_counter() - start

def benchmark_determinant(n=2500, rng=None):
    if rng is None:
        rng = np.random
    A = rng.standard_normal((n, n))
    start = time.perf_counter()
    det_val = np.linalg.det(A)
    return time.perf_counter() - start

def compute_validation_hash(times_arr, task_name):
    content = f"{task_name}_min{np.min(times_arr):.8f}_mean{np.mean(times_arr):.8f}_n{len(times_arr)}"
    return hashlib.sha256(content.encode()).hexdigest()[:16]

def main():
    parser = argparse.ArgumentParser(description="Matrix Operations Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    parser.add_argument("--size", choices=["small", "large"],
                       default="small", help="Matrix size: small=2500, large=5000")
    args = parser.parse_args()

    data_source = "synthetic"
    data_description = "random normal matrices (seed 42)"

    print("=" * 70)
    print("PYTHON - Matrix Operations Benchmark (Standardized)")
    print("=" * 70)

    size_map = {"small": 2500, "large": 5000}
    n_matrix = size_map[args.size]
    n_sort = 1000000
    n_runs = 30
    n_warmup = 5

    rng = make_rng(args.data)

    results = {}
    validation_hashes = {}

    print(f"\n  Warming up ({n_warmup} runs)...")
    for _ in range(n_warmup):
        benchmark_matrix_creation_transpose_reshape(n_matrix, rng)
    print("  ✓ Warmup complete")

    # Benchmarks
    tasks = [
        ("matrix_creation", benchmark_matrix_creation_transpose_reshape, n_matrix),
        ("matrix_power", benchmark_matrix_power, n_matrix),
        ("sorting", benchmark_sorting, n_sort),
        ("crossproduct", benchmark_crossproduct, n_matrix),
        ("determinant", benchmark_determinant, n_matrix)
    ]

    for name, func, arg in tasks:
        print(f"\nRunning {name}...")
        for _ in range(n_warmup): func(arg, rng)
        times = [func(arg, rng) for _ in range(n_runs)]
        times_arr = np.array(times)
        v_hash = compute_validation_hash(times_arr, name)
        validation_hashes[name] = v_hash
        results[name] = {
            "mean": float(np.mean(times)),
            "std": float(np.std(times, ddof=1)),
            "min": float(np.min(times)),
            "max": float(np.max(times)),
            "median": float(np.median(times)),
            "times": times,
            "validation_hash": v_hash
        }
        print(f"  ✓ Min: {results[name]['min']:.4f}s (primary)")

    # Save results
    output = {
        "language": "Python",
        "numpy_version": np.__version__,
        "matrix_size": n_matrix,
        "n_runs": n_runs,
        "data_source": data_source,
        "data_description": data_description,
        "methodology": "Minimum time as primary estimator (Chen & Revels 2016)",
        "results": results,
        "validation_hashes": validation_hashes,
    }

    Path("results").mkdir(exist_ok=True)
    VALIDATION_DIR.mkdir(exist_ok=True)
    with open("results/matrix_ops_python.json", "w") as f:
        json.dump(output, f, indent=2)
    with open(VALIDATION_DIR / "matrix_ops_python_results.json", "w") as f:
        json.dump(output, f, indent=2)
    print("✓ Results saved to results/matrix_ops_python.json")

if __name__ == "__main__":
    main()
