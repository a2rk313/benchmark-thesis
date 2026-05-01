#!/usr/bin/env python3
"""
Consolidated Statistical Engine for Thesis Benchmarking.

This module replaces the duplicated academic_stats.py and benchmark_stats.py
with a single, authoritative implementation that computes bootstrap
confidence intervals for the MINIMUM time (the primary estimator).
"""

import numpy as np
import json
import hashlib
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Union
import warnings

# Suppress scipy warnings if not available
try:
    from scipy import stats
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False
    warnings.warn("SciPy not available - using fallback statistical methods")

def sample_array(arr: Union[np.ndarray, List], n_samples: int = 100) -> np.ndarray:
    """
    Sample array elements consistently across languages using linspace + rounding.
    
    Args:
        arr: Input array/list to sample from
        n_samples: Number of samples to take
        
    Returns:
        Sampled elements as numpy array
    """
    if arr is None or len(arr) == 0:
        return np.array([])
        
    flat = np.asarray(arr).flatten()
    len_flat = len(flat)
    
    if len_flat <= n_samples:
        return flat
        
    # Consistent sampling to match Julia/Python/R implementations
    indices = np.round(np.linspace(0, len_flat - 1, n_samples)).astype(int)
    return flat[indices]

def round_val(v: float, precision: int = 6) -> float:
    """
    Round value to specified precision (consistent across languages).
    """
    if isinstance(v, (int, float)):
        return round(float(v), precision)
    return v

def generate_hash(data: Union[np.ndarray, Dict, List], n_samples: int = 100) -> str:
    """
    Generate consistent hash across languages using SHA256 + sampling.
    
    Args:
        data: Data to hash (numeric array, dict, or list)
        n_samples: Number of samples for large arrays (to prevent hash DoS)
        
    Returns:
        16-character hex digest
    """
    if data is None:
        return "0" * 16
        
    try:
        import json
        JSON_AVAILABLE = True
    except ImportError:
        JSON_AVAILABLE = False
        
    content = ""
    
    if isinstance(data, dict):
        # Sort keys for consistent ordering
        keys = sorted(data.keys())
        items = {}
        for k in keys:
            v = data[k]
            if isinstance(v, (np.ndarray, list)) and len(v) > 1:
                sampled = sample_array(v, n_samples)
                items[str(k)] = [round_val(val) for val in sampled]
            else:
                items[str(k)] = round_val(v)
        content = json.dumps(items, separators=(',', ':')) if JSON_AVAILABLE else str(items)
    elif isinstance(data, (np.ndarray, list)):
        if len(data) > 1:
            sampled = sample_array(data, n_samples)
            values = [round_val(val) for val in sampled]
            content = json.dumps(values, separators=(',', ':')) if JSON_AVAILABLE else str(values)
        else:
            content = json.dumps(round_val(data[0] if len(data) > 0 else 0), separators=(',', ':')) if JSON_AVAILABLE else str(round_val(data[0] if len(data) > 0 else 0))
    else:
        content = json.dumps(round_val(data), separators=(',', ':')) if JSON_AVAILABLE else str(round_val(data))
    
    return hashlib.sha256(content.encode()).hexdigest()[:16]

def compute_statistics(
    times: List[float], 
    confidence_level: float = 0.95,
    n_bootstrap: int = 1000
) -> Dict[str, float]:
    """
    Compute comprehensive statistics with bootstrap confidence intervals for MINIMUM.
    
    Args:
        times: List of execution times
        confidence_level: Confidence level for CI (default 0.95)
        n_bootstrap: Number of bootstrap samples (default 1000)
        
    Returns:
        Dictionary of statistics
    """
    times = np.array(times)
    n = len(times)
    
    if n == 0:
        return {
            "mean": 0.0,
            "std": 0.0,
            "min": 0.0,
            "max": 0.0,
            "ci_95_lower": 0.0,
            "ci_95_upper": 0.0,
            "cv": 0.0
        }
    
    # Core descriptive statistics
    mean_time = float(np.mean(times))
    std_time = float(np.std(times))
    min_time = float(np.min(times))
    max_time = float(np.max(times))
    
    # Coefficient of variation
    cv = std_time / mean_time if mean_time > 0 else 0.0
    
    # Bootstrap confidence interval for the MINIMUM (primary estimator!)
    if n_bootstrap > 0 and n > 1:
        bootstrap_mins = []
        for _ in range(n_bootstrap):
            # Sample with replacement
            sample = np.random.choice(times, size=n, replace=True)
            bootstrap_mins.append(np.min(sample))
        
        # Calculate percentiles for confidence interval
        alpha = 1.0 - confidence_level
        lower_percentile = (alpha / 2.0) * 100
        upper_percentile = (1.0 - alpha / 2.0) * 100
        
        ci_lower = float(np.percentile(bootstrap_mins, lower_percentile))
        ci_upper = float(np.percentile(bootstrap_mins, upper_percentile))
    else:
        # Fallback if bootstrap not possible
        ci_lower = min_time
        ci_upper = min_time
    
    return {
        "mean": mean_time,
        "std": std_time,
        "min": min_time,
        "max": max_time,
        "ci_95_lower": ci_lower,
        "ci_95_upper": ci_upper,
        "cv": cv
    }

def run_benchmark(
    func,
    runs: int = 30,
    warmup: int = 5,
    track_memory: bool = False,
    track_cpu: bool = False
) -> Tuple[Dict[str, float], Optional[float], Optional[Dict]]:
    """
    Run benchmark with standardized warmup, timing, and optional resource tracking.
    
    Args:
        func: Function to benchmark
        runs: Number of benchmark runs
        warmup: Number of warmup runs
        track_memory: Whether to track memory usage
        track_cpu: Whether to track CPU frequency
        
    Returns:
        Tuple of (statistics, peak_memory_mb, cpu_stats)
    """
    import time
    
    # Warmup runs
    for _ in range(warmup):
        func()
    
    # Benchmark runs with timing
    times = []
    for _ in range(runs):
        start = time.perf_counter()
        func()
        end = time.perf_counter()
        times.append(end - start)
    
    # Compute statistics for the MINIMUM time (primary estimator)
    stats_dict = compute_statistics(times)
    
    # Memory tracking (if requested)
    peak_memory_mb = None
    if track_memory:
        try:
            import psutil
            import tracemalloc
            
            tracemalloc.start()
            func()  # Run once more for memory measurement
            current, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            
            # Also get system memory info
            process = psutil.Process()
            mem_info = process.memory_info()
            
            peak_memory_mb = {
                "traced_peak_mb": peak / 1024 / 1024,
                "rss_mb": mem_info.rss / 1024 / 1024,
                "vms_mb": mem_info.vms / 1024 / 1024
            }
        except ImportError:
            peak_memory_mb = {"error": "psutil/tracemalloc not available"}
    
    # CPU tracking (if requested)
    cpu_stats = None
    if track_cpu:
        try:
            import psutil
            cpu_stats = {
                "cpu_percent": psutil.cpu_percent(interval=1),
                "cpu_freq": psutil.cpu_freq().current if psutil.cpu_freq() else None
            }
        except ImportError:
            cpu_stats = {"error": "psutil not available"}
    
    return stats_dict, peak_memory_mb, cpu_stats

def generate_latex_table(benchmark_results: Dict) -> str:
    """
    Generate LaTeX table with corrected statistics.
    
    Args:
        benchmark_results: Results dict from benchmark runs
        
    Returns:
        LaTeX table string
    """
    latex_lines = [
        "\\begin{tabular}{lrrrr}",
        "\\toprule",
        "Language & Mean Time (s) & Std Dev (s) & Min Time (s) & 95\\% CI \\\\",
        "\\midrule"
    ]
    
    languages = ["Python", "Julia", "R"]
    
    for lang in languages:
        if lang.lower() in benchmark_results:
            results = benchmark_results[lang.lower()]
            mean_time = results.get("mean", 0.0)
            std_time = results.get("std", 0.0)  # This is correct now
            min_time = results.get("min", 0.0)
            ci_lower = results.get("ci_95_lower", 0.0)
            ci_upper = results.get("ci_95_upper", 0.0)
            
            latex_lines.append(
                f"{lang} & {mean_time:.4f} & {std_time:.4f} & {min_time:.4f} & "
                f"[{ci_lower:.4f}, {ci_upper:.4f}] \\\\"
            )
    
    latex_lines.extend([
        "\\bottomrule",
        "\\end{tabular}"
    ])
    
    return "\n".join(latex_lines)

# Backwards compatibility exports
BenchmarkResult = Dict[str, float]
hash_output = generate_hash

if __name__ == "__main__":
    # Example usage
    def dummy_benchmark():
        import time
        time.sleep(0.01 + np.random.exponential(0.005))
    
    print("Testing core_stats module...")
    stats_dict, memory_mb, cpu_stats = run_benchmark(dummy_benchmark, runs=10, warmup=2)
    print(f"Statistics: {stats_dict}")
    print(f"Memory: {memory_mb}")
    print(f"CPU: {cpu_stats}")
    
    # Test hash generation
    test_data = np.random.randn(1000)
    hash_result = generate_hash(test_data)
    print(f"Hash: {hash_result}")