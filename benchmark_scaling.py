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
# Quick mode uses 10x smaller scales for faster testing
MATRIX_SCALES = {
    'k1': 2500,   # Small (Tedesco k=1)
    'k2': 3500,   # Medium (Tedesco k=2)
    'k3': 5000,   # Large (Tedesco k=3)
    'k4': 7000    # Extra large (Tedesco k=4)
}

MATRIX_SCALES_QUICK = {
    'k1': 500,    # Quick mode
    'k2': 750,
    'k3': 1000,
    'k4': 1500,
}

VECTOR_SCALES = {
    'small': 100_000,
    'medium': 500_000,
    'large': 1_000_000,
    'xlarge': 5_000_000
}

VECTOR_SCALES_QUICK = {
    'small': 10_000,
    'medium': 25_000,
    'large': 50_000,
    'xlarge': 100_000,
}

IO_SCALES = {
    'small': 100_000,
    'medium': 500_000,
    'large': 1_000_000,
    'xlarge': 5_000_000
}

IO_SCALES_QUICK = {
    'small': 10_000,
    'medium': 25_000,
    'large': 50_000,
    'xlarge': 100_000,
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
        """Analyze algorithmic complexity from scaling results using log-log regression.

        Uses rigorous log-log regression (log(t) = k * log(n) + c) to estimate
        the scaling exponent, which directly indicates algorithmic complexity.
        """
        print(f"\n{'='*70}")
        print(f"COMPLEXITY ANALYSIS: {self.name}")
        print(f"{'='*70}")

        scale_names = list(self.scales.keys())

        # Get min times and scale values
        min_times = [self.results[s]['min'] for s in scale_names]
        scale_values = [self.results[s]['scale_value'] for s in scale_names]

        # Log-log regression for scaling exponent estimation
        # log(t) = k * log(n) + c
        # k is the scaling exponent, indicating complexity
        log_times = np.log(min_times)
        log_sizes = np.log(scale_values)

        # Linear regression using np.polyfit (degree 1 for linear)
        try:
            coeffs = np.polyfit(log_sizes, log_times, 1)
            k = coeffs[0]  # Scaling exponent (slope)
            c = coeffs[1]  # Intercept

            # Calculate R-squared for goodness of fit
            y_pred = k * log_sizes + c
            ss_res = np.sum((log_times - y_pred) ** 2)
            ss_tot = np.sum((log_times - np.mean(log_times)) ** 2)
            r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0.0

            print(f"\nLog-Log Regression Results:")
            print(f"  Scaling exponent (k): {k:.3f}")
            print(f"  R²: {r_squared:.4f}")

            # Determine complexity based on scaling exponent
            if r_squared < 0.5:
                complexity = "Uncertain (poor fit)"
            elif k < 1.2:
                complexity = "O(n) - Linear"
            elif k < 1.5:
                complexity = "O(n log n) - Linearithmic"
            elif k < 2.0:
                complexity = "O(n²) - Quadratic"
            elif k < 3.0:
                complexity = "O(n³) - Cubic"
            else:
                complexity = "> O(n³) - Super cubic"

            print(f"  Estimated Complexity: {complexity}")

        except np.linalg.LinAlgError:
            print("\nWarning: Could not perform log-log regression")
            k = None
            r_squared = 0.0

        # Also show pairwise ratios for reference
        print("\nPairwise scaling ratios (for reference):")
        for i in range(len(scale_names) - 1):
            scale_ratio = scale_values[i+1] / scale_values[i]
            time_ratio = min_times[i+1] / min_times[i]
            exp_est = np.log(time_ratio) / np.log(scale_ratio) if scale_ratio > 1 else 0
            print(f"  {scale_names[i]} → {scale_names[i+1]}: scale={scale_ratio:.2f}×, time={time_ratio:.2f}×, exp~{exp_est:.2f}")
    
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
    
    def __init__(self, quick=False):
        scales = MATRIX_SCALES_QUICK if quick else MATRIX_SCALES
        super().__init__('matrix_crossproduct', scales)
    
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
    
    def __init__(self, quick=False):
        scales = MATRIX_SCALES_QUICK if quick else MATRIX_SCALES
        super().__init__('matrix_determinant', scales)
    
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
    
    def __init__(self, quick=False):
        scales = VECTOR_SCALES_QUICK if quick else VECTOR_SCALES
        super().__init__('sorting', scales)
    
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
    
    def __init__(self, quick=False):
        scales = IO_SCALES_QUICK if quick else IO_SCALES
        super().__init__('csv_write', scales)
    
    def run_at_scale(self, scale_name, n_rows):
        try:
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
        except ImportError:
            # Fallback without pandas
            import csv
            data = [(i, np.random.randn(), np.random.choice(['A', 'B', 'C', 'D']))
                    for i in range(n_rows)]
            start = time.perf_counter()
            with open('data/benchmark_scaling.csv', 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['id', 'value', 'category'])
                writer.writerows(data)
            elapsed = time.perf_counter() - start
            Path('data/benchmark_scaling.csv').unlink(missing_ok=True)
        
        return elapsed


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Data Scaling Benchmark Suite')
    parser.add_argument('--quick', action='store_true',
                        help='Use smaller scales for faster testing')
    parser.add_argument('--runs', type=int, default=10,
                        help='Number of runs per scale (default: 10)')
    args = parser.parse_args()
    
    print("="*70)
    print("DATA SCALING BENCHMARK SUITE")
    print("Following Tedesco et al. (2025) methodology")
    if args.quick:
        print("(Quick mode - smaller scales)")
    print("="*70)
    
    # Run all scaling benchmarks
    benchmarks = [
        MatrixCrossProductScaling(quick=args.quick),
        MatrixDeterminantScaling(quick=args.quick),
        SortingScaling(quick=args.quick),
        CSVWriteScaling(quick=args.quick)
    ]
    
    for benchmark in benchmarks:
        benchmark.n_runs = args.runs
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
