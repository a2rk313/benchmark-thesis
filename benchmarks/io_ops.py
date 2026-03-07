#!/usr/bin/env python3
"""
===============================================================================
I/O Operations Benchmark - Python Implementation
===============================================================================
Tests file I/O performance for CSV and binary formats
Tasks: CSV Write/Read, Binary Write/Read, Random Access
===============================================================================
"""

import numpy as np
import pandas as pd
import sys
import json
import time
import os
from pathlib import Path

def benchmark_csv_write(n_rows=1_000_000):
    df = pd.DataFrame({
        'lat': np.random.uniform(-90, 90, n_rows),
        'lon': np.random.uniform(-180, 180, n_rows),
        'device_id': np.random.randint(1, 10000, n_rows)
    })
    output_path = 'data/io_test_python.csv'
    start = time.perf_counter()
    df.to_csv(output_path, index=False)
    elapsed = time.perf_counter() - start
    return elapsed, os.path.getsize(output_path)

def benchmark_csv_read():
    input_path = 'data/io_test_python.csv'
    start = time.perf_counter()
    df = pd.read_csv(input_path)
    elapsed = time.perf_counter() - start
    return elapsed, len(df)

def benchmark_binary_write(n_values=1_000_000):
    arr = np.random.randn(n_values).astype(np.float64)
    output_path = 'data/io_test_python.bin'
    start = time.perf_counter()
    arr.tofile(output_path)
    elapsed = time.perf_counter() - start
    return elapsed, os.path.getsize(output_path)

def benchmark_binary_read():
    input_path = 'data/io_test_python.bin'
    start = time.perf_counter()
    arr = np.fromfile(input_path, dtype=np.float64)
    elapsed = time.perf_counter() - start
    return elapsed, len(arr)

def benchmark_random_access(n_accesses=1000):
    input_path = 'data/io_test_python.csv'
    with open(input_path, 'r') as f:
        n_lines = sum(1 for _ in f)
    line_indices = np.random.randint(0, n_lines, n_accesses)
    start = time.perf_counter()
    with open(input_path, 'r') as f:
        lines = f.readlines()
        for idx in line_indices:
            _ = lines[idx]
    elapsed = time.perf_counter() - start
    return elapsed, n_accesses

def main():
    print("=" * 70)
    print("PYTHON - I/O Operations Benchmark")
    print("=" * 70)
    
    n_csv_rows = 1_000_000
    n_binary_values = 1_000_000
    n_random_accesses = 1000
    n_runs = 10
    
    Path('data').mkdir(exist_ok=True)
    results = {}
    
    print(f"\n[1/5] CSV Write ({n_csv_rows:,} rows)...")
    times, sizes = zip(*[benchmark_csv_write(n_csv_rows) for _ in range(n_runs)])
    results['csv_write'] = {
        'mean': np.mean(times), 'std': np.std(times),
        'file_size_mb': sizes[0] / (1024**2)
    }
    print(f"  ✓ Mean: {results['csv_write']['mean']:.4f}s ± {results['csv_write']['std']:.4f}s")
    
    print(f"\n[2/5] CSV Read ({n_csv_rows:,} rows)...")
    times, rows = zip(*[benchmark_csv_read() for _ in range(n_runs)])
    results['csv_read'] = {
        'mean': np.mean(times), 'std': np.std(times), 'rows_read': rows[0]
    }
    print(f"  ✓ Mean: {results['csv_read']['mean']:.4f}s ± {results['csv_read']['std']:.4f}s")
    
    print(f"\n[3/5] Binary Write ({n_binary_values:,} values)...")
    times, sizes = zip(*[benchmark_binary_write(n_binary_values) for _ in range(n_runs)])
    results['binary_write'] = {
        'mean': np.mean(times), 'std': np.std(times),
        'file_size_mb': sizes[0] / (1024**2)
    }
    print(f"  ✓ Mean: {results['binary_write']['mean']:.4f}s ± {results['binary_write']['std']:.4f}s")
    
    print(f"\n[4/5] Binary Read ({n_binary_values:,} values)...")
    times, vals = zip(*[benchmark_binary_read() for _ in range(n_runs)])
    results['binary_read'] = {
        'mean': np.mean(times), 'std': np.std(times), 'values_read': vals[0]
    }
    print(f"  ✓ Mean: {results['binary_read']['mean']:.4f}s ± {results['binary_read']['std']:.4f}s")
    
    print(f"\n[5/5] Random Access ({n_random_accesses} reads)...")
    times, reads = zip(*[benchmark_random_access(n_random_accesses) for _ in range(n_runs)])
    results['random_access'] = {
        'mean': np.mean(times), 'std': np.std(times), 'lines_read': reads[0]
    }
    print(f"  ✓ Mean: {results['random_access']['mean']:.4f}s ± {results['random_access']['std']:.4f}s")
    
    print("\n" + "=" * 70)
    print("SAVING RESULTS...")
    print("=" * 70)
    
    output = {
        'language': 'Python',
        'pandas_version': pd.__version__,
        'numpy_version': np.__version__,
        'n_csv_rows': n_csv_rows,
        'n_binary_values': n_binary_values,
        'n_random_accesses': n_random_accesses,
        'n_runs': n_runs,
        'results': results
    }
    
    with open('results/io_ops_python.json', 'w') as f:
        json.dump(output, f, indent=2)
    
    print("✓ Results saved to: results/io_ops_python.json")
    
    print("\nCleaning up test files...")
    for path in ['data/io_test_python.csv', 'data/io_test_python.bin']:
        if os.path.exists(path):
            os.remove(path)
    print("✓ Cleanup complete")

if __name__ == "__main__":
    main()
