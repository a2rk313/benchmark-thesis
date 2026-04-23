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

import numpy as np
import json
import time

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"




def benchmark_matrix_creation_transpose_reshape(n=2500):
    start = time.perf_counter()
    A = np.random.randn(n, n)
    A = A.T
    new_rows = int(n * 2 / 5)
    new_cols = int(n * n / new_rows)
    A = A.reshape(new_rows, new_cols)
    A = A.T
    return time.perf_counter() - start

def benchmark_matrix_power(n=2500):
    A = np.random.randn(n, n)
    A = np.abs(A) / 2.0
    start = time.perf_counter()
    A_pow = np.power(A, 10)
    return time.perf_counter() - start

def benchmark_sorting(n=1000000):
    arr = np.random.randn(n)
    start = time.perf_counter()
    np.sort(arr)
    return time.perf_counter() - start

def benchmark_crossproduct(n=2500):
    A = np.random.randn(n, n)
    start = time.perf_counter()
    B = A.T @ A
    return time.perf_counter() - start

def benchmark_determinant(n=2500):
    A = np.random.randn(n, n)
    start = time.perf_counter()
    det_val = np.linalg.det(A)
    return time.perf_counter() - start

def main():
    print("=" * 70)
    print("PYTHON - Matrix Operations Benchmark (Standardized)")
    print("=" * 70)

    n_matrix = 2500
    n_sort = 1000000
    n_runs = 30
    n_warmup = 5

    results = {}

    print(f"\n  Warming up ({n_warmup} runs)...")
    for _ in range(n_warmup):
        benchmark_matrix_creation_transpose_reshape(n_matrix)
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
        for _ in range(n_warmup): func(arg)
        times = [func(arg) for _ in range(n_runs)]
        results[name] = {
            "mean": float(np.mean(times)),
            "std": float(np.std(times)),
            "min": float(np.min(times)),
            "max": float(np.max(times)),
            "times": times
        }
        print(f"  ✓ Min: {results[name]["min"]:.4f}s (primary)")

    # Save results
    output = {
        "language": "Python",
        "numpy_version": np.__version__,
        "matrix_size": n_matrix,
        "n_runs": n_runs,
        "methodology": "Minimum time as primary estimator (Chen & Revels 2016)",
        "results": results,
    }

    Path("results").mkdir(exist_ok=True)
    with open("results/matrix_ops_python.json", "w") as f:
        json.dump(output, f, indent=2)
    print("✓ Results saved to results/matrix_ops_python.json")

if __name__ == "__main__":
    main()