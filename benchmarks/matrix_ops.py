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

def benchmark_matrix_creation_transpose_reshape(n=2500):
    start = time.perf_counter()
    A = np.random.randn(n, n)
    A = A.T
    new_rows = int(n * 3 / 5)
    new_cols = int(n * 5 / 3)
    A = A.reshape(new_rows, new_cols)
    A = A.T
    elapsed = time.perf_counter() - start
    return elapsed

def benchmark_matrix_power(n=2500):
    A = np.random.randn(n, n)
    A = np.abs(A) / 2.0
    start = time.perf_counter()
    A_pow = np.power(A, 10)
    elapsed = time.perf_counter() - start
    return elapsed

def benchmark_sorting(n=1_000_000):
    arr = np.random.randn(n)
    start = time.perf_counter()
    arr_sorted = np.sort(arr)
    elapsed = time.perf_counter() - start
    return elapsed

def benchmark_crossproduct(n=2500):
    A = np.random.randn(n, n)
    start = time.perf_counter()
    B = A.T @ A
    elapsed = time.perf_counter() - start
    return elapsed

def benchmark_determinant(n=2500):
    A = np.random.randn(n, n)
    start = time.perf_counter()
    det_val = np.linalg.det(A)
    elapsed = time.perf_counter() - start
    return elapsed

def main():
    print("=" * 70)
    print("PYTHON - Matrix Operations Benchmark")
    print("=" * 70)
    
    n_matrix = 2500
    n_sort = 1_000_000
    n_runs = 10
    
    results = {}
    
    print(f"\n[1/5] Matrix Creation + Transpose + Reshape ({n_matrix}×{n_matrix})...")
    times = [benchmark_matrix_creation_transpose_reshape(n_matrix) for _ in range(n_runs)]
    results['matrix_creation'] = {
        'mean': np.mean(times), 'std': np.std(times), 'min': np.min(times), 'max': np.max(times)
    }
    print(f"  ✓ Mean: {results['matrix_creation']['mean']:.4f}s ± {results['matrix_creation']['std']:.4f}s")
    
    print(f"\n[2/5] Matrix Exponentiation ^10 ({n_matrix}×{n_matrix})...")
    times = [benchmark_matrix_power(n_matrix) for _ in range(n_runs)]
    results['matrix_power'] = {
        'mean': np.mean(times), 'std': np.std(times), 'min': np.min(times), 'max': np.max(times)
    }
    print(f"  ✓ Mean: {results['matrix_power']['mean']:.4f}s ± {results['matrix_power']['std']:.4f}s")
    
    print(f"\n[3/5] Sorting {n_sort:,} Random Values...")
    times = [benchmark_sorting(n_sort) for _ in range(n_runs)]
    results['sorting'] = {
        'mean': np.mean(times), 'std': np.std(times), 'min': np.min(times), 'max': np.max(times)
    }
    print(f"  ✓ Mean: {results['sorting']['mean']:.4f}s ± {results['sorting']['std']:.4f}s")
    
    print(f"\n[4/5] Cross-Product A'A ({n_matrix}×{n_matrix})...")
    times = [benchmark_crossproduct(n_matrix) for _ in range(n_runs)]
    results['crossproduct'] = {
        'mean': np.mean(times), 'std': np.std(times), 'min': np.min(times), 'max': np.max(times)
    }
    print(f"  ✓ Mean: {results['crossproduct']['mean']:.4f}s ± {results['crossproduct']['std']:.4f}s")
    
    print(f"\n[5/5] Matrix Determinant ({n_matrix}×{n_matrix})...")
    times = [benchmark_determinant(n_matrix) for _ in range(n_runs)]
    results['determinant'] = {
        'mean': np.mean(times), 'std': np.std(times), 'min': np.min(times), 'max': np.max(times)
    }
    print(f"  ✓ Mean: {results['determinant']['mean']:.4f}s ± {results['determinant']['std']:.4f}s")
    
    print("\n" + "=" * 70)
    print("SAVING RESULTS...")
    print("=" * 70)
    
    output = {
        'language': 'Python',
        'numpy_version': np.__version__,
        'matrix_size': n_matrix,
        'sorting_size': n_sort,
        'n_runs': n_runs,
        'results': results
    }
    
    with open('results/matrix_ops_python.json', 'w') as f:
        json.dump(output, f, indent=2)
    
    print("✓ Results saved to: results/matrix_ops_python.json")

if __name__ == "__main__":
    main()
