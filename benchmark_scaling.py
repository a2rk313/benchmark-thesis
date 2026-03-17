#!/usr/bin/env python3
"""
===============================================================================
Data Scaling Benchmark Framework
===============================================================================
Runs benchmarks at multiple data scales to:
1. Validate algorithmic complexity
2. Identify performance cliffs
3. Improve statistical reliability
4. Follow Tedesco et al. (2025) methodology (k=1,2,3,4)
===============================================================================
"""

import numpy as np
import json
import time
from pathlib import Path

# Scaling configurations (following Tedesco et al. 2025)
MATRIX_SCALES = {
    'k1': 2500,   # Small (Tedesco k=1)
    'k2': 3500,   # Medium (Tedesco k=2)
    'k3': 5000,   # Large (Tedesco k=3)
    'k4': 7000    # Extra large (Tedesco k=4)
}

VECTOR_SCALES = {
    'small': 100_000,
    'medium': 500_000,
    'large': 1_000_000,
    'xlarge': 5_000_000
}

IO_SCALES = {
    'small': 100_000,
    'medium': 500_000,
    'large': 1_000_000,
    'xlarge': 5_000_000
}

class ScalingBenchmark:
    """Base class for scaling benchmarks."""
    
    def __init__(self, name, scales, n_runs=10):
        self.name = name
        self.scales = scales
        self.n_runs = n_runs
        self.results = {}
    
    def run_at_scale(self, scale_name, scale_value):
        """Override this in subclasses."""
        raise NotImplementedError
    
    def run_all_scales(self):
        """Run benchmark at all scales."""
        print(f"\n{'='*70}")
        print(f"SCALING BENCHMARK: {self.name}")
        print(f"{'='*70}")
        
        for scale_name, scale_value in self.scales.items():
            print(f"\n[{scale_name}] Scale: {scale_value:,}")
            
            times = []
            for run in range(self.n_runs):
                elapsed = self.run_at_scale(scale_name, scale_value)
                times.append(elapsed)
                print(f"  Run {run+1}/{self.n_runs}: {elapsed:.4f}s")
            
            self.results[scale_name] = {
                'scale_value': scale_value,
                'min': float(np.min(times)),
                'mean': float(np.mean(times)),
                'median': float(np.median(times)),
                'std': float(np.std(times)),
                'max': float(np.max(times)),
                'all_times': [float(t) for t in times]
            }
            
            print(f"  ✓ Min: {self.results[scale_name]['min']:.4f}s (PRIMARY)")
            print(f"    Mean: {self.results[scale_name]['mean']:.4f}s ± {self.results[scale_name]['std']:.4f}s")
    
    def analyze_complexity(self):
        """Analyze algorithmic complexity from scaling results."""
        print(f"\n{'='*70}")
        print(f"COMPLEXITY ANALYSIS: {self.name}")
        print(f"{'='*70}")
        
        scale_names = list(self.scales.keys())
        
        # Get min times and scale values
        min_times = [self.results[s]['min'] for s in scale_names]
        scale_values = [self.results[s]['scale_value'] for s in scale_names]
        
        # Calculate ratios
        print("\nScaling ratios (min times):")
        for i in range(len(scale_names) - 1):
            scale_ratio = scale_values[i+1] / scale_values[i]
            time_ratio = min_times[i+1] / min_times[i]
            
            # Estimate complexity
            if time_ratio < scale_ratio * 1.2:
                complexity = "O(n) or better"
            elif time_ratio < scale_ratio**2 * 1.2:
                complexity = "Between O(n) and O(n²)"
            elif time_ratio < scale_ratio**3 * 1.2:
                complexity = "O(n²) or O(n³)"
            else:
                complexity = "> O(n³)"
            
            print(f"  {scale_names[i]} → {scale_names[i+1]}:")
            print(f"    Scale ratio: {scale_ratio:.2f}×")
            print(f"    Time ratio:  {time_ratio:.2f}×")
            print(f"    Estimated complexity: {complexity}")
    
    def save_results(self, output_dir='results/scaling'):
        """Save scaling results to JSON."""
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        output_file = f"{output_dir}/{self.name}_scaling.json"
        
        output = {
            'benchmark': self.name,
            'scales': self.scales,
            'n_runs': self.n_runs,
            'methodology': 'Chen & Revels (2016): minimum as primary estimator',
            'results': self.results
        }
        
        with open(output_file, 'w') as f:
            json.dump(output, f, indent=2)
        
        print(f"\n✓ Results saved to: {output_file}")


class MatrixCrossProductScaling(ScalingBenchmark):
    """Matrix cross-product at multiple scales."""
    
    def __init__(self):
        super().__init__('matrix_crossproduct', MATRIX_SCALES)
    
    def run_at_scale(self, scale_name, n):
        # Pre-generate matrix (not timed)
        A = np.random.randn(n, n)
        
        # Timed operation
        start = time.perf_counter()
        B = A.T @ A
        elapsed = time.perf_counter() - start
        
        return elapsed


class MatrixDeterminantScaling(ScalingBenchmark):
    """Matrix determinant at multiple scales."""
    
    def __init__(self):
        super().__init__('matrix_determinant', MATRIX_SCALES)
    
    def run_at_scale(self, scale_name, n):
        # Pre-generate matrix
        A = np.random.randn(n, n)
        
        # Timed operation
        start = time.perf_counter()
        det = np.linalg.det(A)
        elapsed = time.perf_counter() - start
        
        return elapsed


class SortingScaling(ScalingBenchmark):
    """Sorting at multiple scales."""
    
    def __init__(self):
        super().__init__('sorting', VECTOR_SCALES)
    
    def run_at_scale(self, scale_name, n):
        # Pre-generate data
        arr = np.random.randn(n)
        
        # Timed operation
        start = time.perf_counter()
        sorted_arr = np.sort(arr)
        elapsed = time.perf_counter() - start
        
        return elapsed


class CSVWriteScaling(ScalingBenchmark):
    """CSV write at multiple scales."""
    
    def __init__(self):
        super().__init__('csv_write', IO_SCALES)
    
    def run_at_scale(self, scale_name, n_rows):
        import pandas as pd
        
        # Pre-generate data
        df = pd.DataFrame({
            'id': range(n_rows),
            'value': np.random.randn(n_rows),
            'category': np.random.choice(['A', 'B', 'C', 'D'], n_rows)
        })
        
        # Timed operation
        start = time.perf_counter()
        df.to_csv('data/benchmark_scaling.csv', index=False)
        elapsed = time.perf_counter() - start
        
        # Cleanup
        Path('data/benchmark_scaling.csv').unlink(missing_ok=True)
        
        return elapsed


def main():
    print("="*70)
    print("DATA SCALING BENCHMARK SUITE")
    print("Following Tedesco et al. (2025) methodology")
    print("="*70)
    
    # Run all scaling benchmarks
    benchmarks = [
        MatrixCrossProductScaling(),
        MatrixDeterminantScaling(),
        SortingScaling(),
        CSVWriteScaling()
    ]
    
    for benchmark in benchmarks:
        benchmark.run_all_scales()
        benchmark.analyze_complexity()
        benchmark.save_results()
    
    print("\n" + "="*70)
    print("SCALING ANALYSIS COMPLETE")
    print("="*70)
    print("\nGenerated files:")
    print("  - results/scaling/*_scaling.json")
    print("\nNext steps:")
    print("  1. Run: python3 tools/visualize_scaling.py")
    print("  2. Review complexity estimates")
    print("  3. Include scaling plots in thesis")


if __name__ == "__main__":
    main()
