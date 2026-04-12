#!/usr/bin/env python3
"""
================================================================================
Scaling Analysis & Visualization Tool
================================================================================
Analyzes scaling benchmark results and generates publication-quality plots
================================================================================
"""

import numpy as np
import json
import glob
import sys
from pathlib import Path

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("Warning: matplotlib not installed. Visualization skipped.")
    print("Install with: pip install matplotlib seaborn")

try:
    from scipy.optimize import curve_fit
    from scipy.stats import linregress
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False
    print("Warning: scipy not installed. Complexity fitting skipped.")

# Complexity functions for fitting
def linear(x, a, b):
    """O(n)"""
    return a * x + b

def quadratic(x, a, b, c):
    """O(n²)"""
    return a * x**2 + b * x + c

def nlogn(x, a, b):
    """O(n log n)"""
    return a * x * np.log(x) + b

def cubic(x, a, b):
    """O(n³)"""
    return a * x**3 + b


class ScalingAnalyzer:
    """Analyze and visualize scaling benchmark results."""
    
    def __init__(self, results_dir='results/scaling'):
        self.results_dir = results_dir
        self.results = {}
        self.load_results()
    
    def load_results(self):
        """Load all scaling results."""
        result_files = glob.glob(f'{self.results_dir}/*_scaling.json')
        
        for result_file in result_files:
            with open(result_file) as f:
                data = json.load(f)
                benchmark_name = data['benchmark']
                self.results[benchmark_name] = data
        
        print(f"✓ Loaded {len(self.results)} scaling benchmarks")
    
    def plot_scaling(self, benchmark_name, save=True):
        """Plot scaling behavior for a benchmark."""
        if benchmark_name not in self.results:
            print(f"❌ Benchmark '{benchmark_name}' not found")
            return None, None
        
        if not HAS_MATPLOTLIB:
            print("  Skipping plot (matplotlib not installed)")
            return self._estimate_complexity(benchmark_name)
        
        data = self.results[benchmark_name]
        results = data['results']
        
        # Extract data
        scale_names = list(results.keys())
        scale_values = np.array([results[s]['scale_value'] for s in scale_names])
        min_times = np.array([results[s]['min'] for s in scale_names])
        mean_times = np.array([results[s]['mean'] for s in scale_names])
        std_times = np.array([results[s]['std'] for s in scale_names])
        
        # Create plot
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
        
        # Plot 1: Absolute times
        ax1.errorbar(scale_values, mean_times, yerr=std_times, 
                     fmt='o-', capsize=5, label='Mean ± std', alpha=0.7)
        ax1.plot(scale_values, min_times, '^-', label='Minimum (primary)', 
                 linewidth=2, markersize=8)
        
        # Try to fit complexity curves
        if HAS_SCIPY:
            try:
                # Try O(n log n) fit
                popt_nlogn, _ = curve_fit(nlogn, scale_values, min_times)
                fit_nlogn = nlogn(scale_values, *popt_nlogn)
                ax1.plot(scale_values, fit_nlogn, '--', alpha=0.5, 
                         label='O(n log n) fit', linewidth=1.5)
            except:
                pass
            
            try:
                # Try O(n²) fit
                popt_quad, _ = curve_fit(quadratic, scale_values, min_times)
                fit_quad = quadratic(scale_values, *popt_quad)
                ax1.plot(scale_values, fit_quad, '--', alpha=0.5, 
                         label='O(n²) fit', linewidth=1.5)
            except:
                pass
        
        ax1.set_xlabel('Data Size (n)', fontsize=12)
        ax1.set_ylabel('Time (seconds)', fontsize=12)
        ax1.set_title(f'Scaling: {benchmark_name}', fontsize=14, fontweight='bold')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # Plot 2: Log-log for complexity analysis
        ax2.loglog(scale_values, min_times, 'o-', linewidth=2, markersize=8,
                   label='Minimum time')
        
        # Linear fit in log-log space to estimate exponent
        slope, r_squared = self._estimate_complexity(benchmark_name)
        
        if HAS_SCIPY and slope is not None:
            log_scale = np.log(scale_values)
            log_time = np.log(min_times)
            slope, intercept, r_value, p_value, std_err = linregress(log_scale, log_time)
            r_squared = r_value**2
            
            # Plot fitted line
            fit_log = np.exp(intercept) * scale_values**slope
            ax2.loglog(scale_values, fit_log, '--', alpha=0.7,
                       label=f'Fit: O(n^{slope:.2f}), R²={r_squared:.3f}')
        
        # Add reference lines
        ref_linear = min_times[0] * (scale_values / scale_values[0])
        ref_quad = min_times[0] * (scale_values / scale_values[0])**2
        
        ax2.loglog(scale_values, ref_linear, ':', alpha=0.4, label='O(n) reference')
        ax2.loglog(scale_values, ref_quad, ':', alpha=0.4, label='O(n²) reference')
        
        ax2.set_xlabel('Data Size (n)', fontsize=12)
        ax2.set_ylabel('Time (seconds)', fontsize=12)
        ax2.set_title('Log-Log Plot (Complexity Estimation)', fontsize=14, fontweight='bold')
        ax2.legend()
        ax2.grid(True, alpha=0.3, which='both')
        
        plt.tight_layout()
        
        if save:
            output_file = f'{self.results_dir}/{benchmark_name}_scaling_plot.png'
            plt.savefig(output_file, dpi=300, bbox_inches='tight')
            print(f"✓ Saved: {output_file}")
        else:
            plt.show()
        
        plt.close()
        
        return slope, r_squared
    
    def _estimate_complexity(self, benchmark_name):
        """Estimate complexity without plotting."""
        if benchmark_name not in self.results:
            return None, None
        
        results = self.results[benchmark_name]['results']
        scale_names = list(results.keys())
        scale_values = np.array([results[s]['scale_value'] for s in scale_names])
        min_times = np.array([results[s]['min'] for s in scale_names])
        
        if len(scale_values) < 2:
            return None, None
        
        if not HAS_SCIPY:
            return None, None
        
        # Simple ratio-based estimation
        log_scale = np.log(scale_values)
        log_time = np.log(min_times)
        
        try:
            from scipy.stats import linregress
            slope, intercept, r_value, _, _ = linregress(log_scale, log_time)
            return slope, r_value**2
        except:
            return None, None
    
    def generate_comparison_table(self):
        """Generate comparison table across all benchmarks."""
        print("\n" + "="*80)
        print("SCALING CHARACTERISTICS SUMMARY")
        print("="*80)
        
        print(f"\n{'Benchmark':<25} {'Complexity':<15} {'R²':<10} {'Interpretation'}")
        print("-"*80)
        
        for benchmark_name in self.results:
            slope, r_squared = self.plot_scaling(benchmark_name, save=True)
            
            # Interpret complexity
            if slope < 1.2:
                complexity = "O(n)"
            elif slope < 1.5:
                complexity = "O(n log n)"
            elif slope < 2.2:
                complexity = "O(n²)"
            elif slope < 3.2:
                complexity = "O(n³)"
            else:
                complexity = f"O(n^{slope:.1f})"
            
            interpretation = "Excellent" if r_squared > 0.99 else "Good" if r_squared > 0.95 else "Fair"
            
            print(f"{benchmark_name:<25} {complexity:<15} {r_squared:<10.4f} {interpretation}")
    
    def generate_multi_benchmark_plot(self):
        """Plot multiple benchmarks on same axes for comparison."""
        if not HAS_MATPLOTLIB:
            print("\nSkipping multi-benchmark plot (matplotlib not installed)")
            return
        
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
        
        colors = plt.cm.tab10(np.linspace(0, 1, len(self.results)))
        
        for i, (benchmark_name, data) in enumerate(self.results.items()):
            results = data['results']
            
            scale_names = list(results.keys())
            scale_values = np.array([results[s]['scale_value'] for s in scale_names])
            min_times = np.array([results[s]['min'] for s in scale_names])
            
            # Normalize to first data point
            normalized_times = min_times / min_times[0]
            normalized_scale = scale_values / scale_values[0]
            
            ax1.plot(normalized_scale, normalized_times, 'o-', 
                     label=benchmark_name, color=colors[i], linewidth=2)
            
            ax2.loglog(normalized_scale, normalized_times, 'o-',
                       label=benchmark_name, color=colors[i], linewidth=2)
        
        # Add reference lines
        ref_x = np.array([1, 3])
        ax1.plot(ref_x, ref_x, 'k--', alpha=0.3, label='O(n) reference')
        ax1.plot(ref_x, ref_x**2, 'k:', alpha=0.3, label='O(n²) reference')
        
        ax2.loglog(ref_x, ref_x, 'k--', alpha=0.3, label='O(n)')
        ax2.loglog(ref_x, ref_x**2, 'k:', alpha=0.3, label='O(n²)')
        
        ax1.set_xlabel('Relative Data Size', fontsize=12)
        ax1.set_ylabel('Relative Time', fontsize=12)
        ax1.set_title('Normalized Scaling Comparison', fontsize=14, fontweight='bold')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        ax2.set_xlabel('Relative Data Size (log)', fontsize=12)
        ax2.set_ylabel('Relative Time (log)', fontsize=12)
        ax2.set_title('Log-Log Normalized Comparison', fontsize=14, fontweight='bold')
        ax2.legend()
        ax2.grid(True, alpha=0.3, which='both')
        
        plt.tight_layout()
        output_file = f'{self.results_dir}/all_benchmarks_comparison.png'
        plt.savefig(output_file, dpi=300, bbox_inches='tight')
        print(f"\n✓ Multi-benchmark comparison saved: {output_file}")
        plt.close()


def main():
    print("="*80)
    print("SCALING ANALYSIS & VISUALIZATION")
    print("="*80)
    
    analyzer = ScalingAnalyzer()
    
    if not analyzer.results:
        print("\n❌ No scaling results found!")
        print("   Run: python3 benchmark_scaling.py first")
        return
    
    # Generate individual plots and analysis
    analyzer.generate_comparison_table()
    
    # Generate multi-benchmark comparison
    analyzer.generate_multi_benchmark_plot()
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE")
    print("="*80)
    print("\nGenerated figures:")
    print("  - results/scaling/*_scaling_plot.png (individual)")
    print("  - results/scaling/all_benchmarks_comparison.png (combined)")
    print("\nUse these figures in thesis Chapter 5 (Results)")


if __name__ == "__main__":
    main()
