#!/usr/bin/env python3
"""
===============================================================================
Matrix Operations Benchmark - Python Implementation
===============================================================================
Reproduces Tedesco et al. (2025) matrix operation benchmarks
Tasks: Creation/Transpose/Reshape, Power, Sorting, Cross-product, Determinant
===============================================================================
"""

import numpy as np
import sys
import json
import time
from pathlib import Path


def benchmark_matrix_creation_transpose_reshape(n=2500):
    """
    Task 1.1: Matrix Creation + Transpose + Reshape
    - Create n×n random matrix
    - Transpose it
    - Reshape to (n*3/5 × n*5/3)
    - Transpose again
    """
    start = time.perf_counter()

    # Create
    A = np.random.randn(n, n)

    # Transpose
    A = A.T

    # Reshape
    new_rows = int(n * 2 / 5)
    new_cols = int(n * n / new_rows)
    A = A.reshape(new_rows, new_cols)

    # Transpose again
    A = A.T

    elapsed = time.perf_counter() - start
    return elapsed


def benchmark_matrix_power(n=2500):
    """
    Task 1.2: Element-wise Matrix Exponentiation
    - Create n×n random matrix
    - Take absolute value and divide by 2
    - Raise to power 10 (element-wise)
    """
    # Pre-generate data (not timed)
    A = np.random.randn(n, n)
    A = np.abs(A) / 2.0

    # Timed operation
    start = time.perf_counter()
    A_pow = np.power(A, 10)
    elapsed = time.perf_counter() - start

    return elapsed


def benchmark_sorting(n=1_000_000):
    """
    Task 1.3: Sorting Random Values
    - Generate n random values
    - Sort them in ascending order
    """
    # Pre-generate data (not timed)
    arr = np.random.randn(n)

    # Timed operation (quicksort is NumPy default)
    start = time.perf_counter()
    arr_sorted = np.sort(arr)
    elapsed = time.perf_counter() - start

    return elapsed


def benchmark_crossproduct(n=2500):
    """
    Task 1.4: Matrix Cross-Product (A'A)
    - Create n×n random matrix
    - Compute A' * A
    """
    # Pre-generate data (not timed)
    A = np.random.randn(n, n)

    # Timed operation
    start = time.perf_counter()
    B = A.T @ A
    elapsed = time.perf_counter() - start

    return elapsed


def benchmark_determinant(n=2500):
    """
    Task 1.5: Matrix Determinant
    - Create n×n random matrix
    - Compute determinant
    """
    # Pre-generate data (not timed)
    A = np.random.randn(n, n)

    # Timed operation
    start = time.perf_counter()
    det_val = np.linalg.det(A)
    elapsed = time.perf_counter() - start

    return elapsed


def main():
    print("=" * 70)
    print("PYTHON - Matrix Operations Benchmark")
    print("=" * 70)

    # Configuration
    n_matrix = 2500  # Matrix size (matching Tedesco et al. k=1)
    n_sort = 1_000_000  # Sorting size
    n_runs = 10  # Number of runs for averaging

    results = {}

    # Task 1: Creation/Transpose/Reshape
    print(f"\n[1/5] Matrix Creation + Transpose + Reshape ({n_matrix}×{n_matrix})...")
    times = [
        benchmark_matrix_creation_transpose_reshape(n_matrix) for _ in range(n_runs)
    ]
    results["matrix_creation"] = {
        "mean": float(np.mean(times)),
        "std": float(np.std(times)),
        "min": float(np.min(times)),
        "max": float(np.max(times)),
    }
    print(f"  ✓ Min: {results['matrix_creation']['min']:.4f}s (primary)")
    print(
        f"  ✓ Mean: {results['matrix_creation']['mean']:.4f}s ± {results['matrix_creation']['std']:.4f}s"
    )

    # Task 2: Matrix Power
    print(f"\n[2/5] Matrix Exponentiation ^10 ({n_matrix}×{n_matrix})...")
    times = [benchmark_matrix_power(n_matrix) for _ in range(n_runs)]
    results["matrix_power"] = {
        "mean": float(np.mean(times)),
        "std": float(np.std(times)),
        "min": float(np.min(times)),
        "max": float(np.max(times)),
    }
    print(f"  ✓ Min: {results['matrix_power']['min']:.4f}s (primary)")
    print(
        f"  ✓ Mean: {results['matrix_power']['mean']:.4f}s ± {results['matrix_power']['std']:.4f}s"
    )

    # Task 3: Sorting
    print(f"\n[3/5] Sorting {n_sort:,} Random Values...")
    times = [benchmark_sorting(n_sort) for _ in range(n_runs)]
    results["sorting"] = {
        "mean": float(np.mean(times)),
        "std": float(np.std(times)),
        "min": float(np.min(times)),
        "max": float(np.max(times)),
    }
    print(f"  ✓ Min: {results['sorting']['min']:.4f}s (primary)")
    print(
        f"  ✓ Mean: {results['sorting']['mean']:.4f}s ± {results['sorting']['std']:.4f}s"
    )

    # Task 4: Cross-product
    print(f"\n[4/5] Cross-Product A'A ({n_matrix}×{n_matrix})...")
    times = [benchmark_crossproduct(n_matrix) for _ in range(n_runs)]
    results["crossproduct"] = {
        "mean": float(np.mean(times)),
        "std": float(np.std(times)),
        "min": float(np.min(times)),
        "max": float(np.max(times)),
    }
    print(f"  ✓ Min: {results['crossproduct']['min']:.4f}s (primary)")
    print(
        f"  ✓ Mean: {results['crossproduct']['mean']:.4f}s ± {results['crossproduct']['std']:.4f}s"
    )

    # Task 5: Determinant
    print(f"\n[5/5] Matrix Determinant ({n_matrix}×{n_matrix})...")
    times = [benchmark_determinant(n_matrix) for _ in range(n_runs)]
    results["determinant"] = {
        "mean": float(np.mean(times)),
        "std": float(np.std(times)),
        "min": float(np.min(times)),
        "max": float(np.max(times)),
    }
    print(f"  ✓ Min: {results['determinant']['min']:.4f}s (primary)")
    print(
        f"  ✓ Mean: {results['determinant']['mean']:.4f}s ± {results['determinant']['std']:.4f}s"
    )

    # Save results
    print("\n" + "=" * 70)
    print("SAVING RESULTS...")
    print("=" * 70)

    output = {
        "language": "Python",
        "numpy_version": np.__version__,
        "matrix_size": n_matrix,
        "sorting_size": n_sort,
        "n_runs": n_runs,
        "methodology": "Minimum time as primary estimator (Chen & Revels 2016)",
        "results": results,
    }

    Path("results").mkdir(exist_ok=True)
    with open("results/matrix_ops_python.json", "w") as f:
        json.dump(output, f, indent=2)

    print("✓ Results saved to: results/matrix_ops_python.json")
    print("\nNote: Minimum times are primary metrics (Chen & Revels 2016)")
    print("      Mean/median provided for context only")


if __name__ == "__main__":
    main()
