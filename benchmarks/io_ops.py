#!/usr/bin/env python3
"""
===============================================================================
I/O Operations Benchmark - Python Implementation
===============================================================================
Tests file I/O performance for CSV and binary formats
Tasks: CSV Write/Read, Binary Write/Read
===============================================================================
"""
from pathlib import Path

import numpy as np
import pandas as pd
import sys
import json
import time
import os
import gc

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"




def benchmark_csv_write(n_rows=1_000_000):
    """Task 1: Write CSV File using PyArrow engine."""
    df = pd.DataFrame({
        'lat': np.random.uniform(-90, 90, n_rows),
        'lon': np.random.uniform(-180, 180, n_rows),
        'device_id': np.random.randint(1, 10000, n_rows)
    })
    output_path = 'data/io_test_python.csv'
    start = time.perf_counter()
    df.to_csv(output_path, index=False, engine='pyarrow')
    elapsed = time.perf_counter() - start
    return elapsed, os.path.getsize(output_path)

def benchmark_csv_read():
    """Task 2: Read CSV File using PyArrow engine."""
    input_path = 'data/io_test_python.csv'
    start = time.perf_counter()
    df = pd.read_csv(input_path, engine='pyarrow')
    elapsed = time.perf_counter() - start
    return elapsed, len(df)

def benchmark_binary_write(n_values=1_000_000):
    """Task 3: Write Binary File."""
    arr = np.random.randn(n_values).astype(np.float64)
    output_path = 'data/io_test_python.bin'
    start = time.perf_counter()
    arr.tofile(output_path)
    elapsed = time.perf_counter() - start
    return elapsed, os.path.getsize(output_path)

def benchmark_binary_read():
    """Task 4: Read Binary File."""
    input_path = 'data/io_test_python.bin'
    start = time.perf_counter()
    arr = np.fromfile(input_path, dtype=np.float64)
    elapsed = time.perf_counter() - start
    return elapsed, len(arr)

def main():
    print("=" * 70)
    print("PYTHON - I/O Operations Benchmark")
    print("=" * 70)
    
    n_csv_rows = 1_000_000
    n_binary_values = 1_000_000
    n_runs = 30
    n_warmup = 5
    Path('data').mkdir(exist_ok=True)
    results = {}
    
    # Task 1: CSV Write
    print(f"\n[1/4] CSV Write ({n_csv_rows:,} rows)...")
    for _ in range(n_warmup): benchmark_csv_write(n_csv_rows)
    times = []
    file_size = 0
    for _ in range(n_runs):
        gc.collect()
        t, size = benchmark_csv_write(n_csv_rows)
        times.append(t)
        file_size = size
    results['csv_write'] = {'mean': float(np.mean(times)), 'std': float(np.std(times)), 'min': float(np.min(times)), 'max': float(np.max(times)), 'file_size_mb': float(file_size / (1024**2))}
    print(f"  ✓ Min: {results['csv_write']['min']:.4f}s")

    # Task 2: CSV Read
    print(f"\n[2/4] CSV Read ({n_csv_rows:,} rows)...")
    for _ in range(n_warmup): benchmark_csv_read()
    times = []
    for _ in range(n_runs):
        gc.collect()
        t, rows = benchmark_csv_read()
        times.append(t)
    results['csv_read'] = {'mean': float(np.mean(times)), 'std': float(np.std(times)), 'min': float(np.min(times)), 'max': float(np.max(times)), 'rows_read': int(n_csv_rows)}
    print(f"  ✓ Min: {results['csv_read']['min']:.4f}s")

    # Task 3: Binary Write
    print(f"\n[3/4] Binary Write ({n_binary_values:,} float64 values)...")
    for _ in range(n_warmup): benchmark_binary_write(n_binary_values)
    times = []
    for _ in range(n_runs):
        gc.collect()
        t, size = benchmark_binary_write(n_binary_values)
        times.append(t)
        file_size = size
    results['binary_write'] = {'mean': float(np.mean(times)), 'std': float(np.std(times)), 'min': float(np.min(times)), 'max': float(np.max(times)), 'file_size_mb': float(file_size / (1024**2))}
    print(f"  ✓ Min: {results['binary_write']['min']:.4f}s")

    # Task 4: Binary Read
    print(f"\n[4/4] Binary Read ({n_binary_values:,} float64 values)...")
    for _ in range(n_warmup): benchmark_binary_read()
    times = []
    for _ in range(n_runs):
        gc.collect()
        t, vals = benchmark_binary_read()
        times.append(t)
    results['binary_read'] = {'mean': float(np.mean(times)), 'std': float(np.std(times)), 'min': float(np.min(times)), 'max': float(np.max(times)), 'values_read': int(n_binary_values)}
    print(f"  ✓ Min: {results['binary_read']['min']:.4f}s")

    output = {'language': 'Python', 'results': results}
    Path('results').mkdir(exist_ok=True)
    with open('results/io_ops_python.json', 'w') as f: json.dump(output, f, indent=2)
    print("✓ Results saved to: results/io_ops_python.json")
    for path in ['data/io_test_python.csv', 'data/io_test_python.bin']:
        if os.path.exists(path): os.remove(path)

if __name__ == "__main__":
    main()