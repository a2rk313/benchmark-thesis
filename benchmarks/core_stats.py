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
import math
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
    std_time = float(np.std(times, ddof=1))  # Sample std (ddof=1)
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
            std_time = results.get("std", 0.0)
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


# =============================================================================
# Additional statistical functions (moved from benchmark_stats.py)
# =============================================================================

def median_of_means(times: np.ndarray, n_blocks: Optional[int] = None) -> Tuple[float, int]:
    """
    Compute median-of-means estimator for robust central tendency.
    """
    n = len(times)
    if n_blocks is None:
        n_blocks = max(3, int(np.sqrt(n)))
    n_blocks = min(n_blocks, n)
    block_size = n // n_blocks
    if block_size < 2:
        return float(np.median(times)), 1
    block_means = []
    for i in range(n_blocks):
        start = i * block_size
        end = start + block_size if i < n_blocks - 1 else n
        block_means.append(np.mean(times[start:end]))
    return float(np.median(block_means)), n_blocks


def dagostino_pearson_test(times: np.ndarray) -> Tuple[float, bool]:
    """
    D'Agostino-Pearson K² test for normality.
    """
    n = len(times)
    if n < 20:
        return 1.0, True
    if SCIPY_AVAILABLE:
        try:
            stat, p = stats.normaltest(times)
            return float(p), float(p) > 0.05
        except Exception:
            pass
    x = np.asarray(times)
    mean = np.mean(x)
    std = float(np.std(x, ddof=1))
    if std == 0:
        return 1.0, True
    skewness = float(np.sum(((x - mean) / std) ** 3) / n)
    kurtosis = float(np.sum(((x - mean) / std) ** 4) / n - 3)
    b1 = skewness ** 2
    b2 = kurtosis ** 2
    A = 0.5 * b1 + 0.25 * b2
    chi2_stat = A * (n - 1)
    if SCIPY_AVAILABLE:
        try:
            p_value = float(1 - stats.chi2.cdf(chi2_stat, df=2))
        except Exception:
            p_value = math.exp(-chi2_stat / 2)
    else:
        p_value = math.exp(-chi2_stat / 2)
    return max(0.001, min(0.999, p_value)), p_value > 0.05


def jarque_bera_test(times: np.ndarray) -> Tuple[float, bool]:
    """
    Jarque-Bera test for normality.
    """
    n = len(times)
    if n < 20:
        return 1.0, True
    if SCIPY_AVAILABLE:
        try:
            stat, p = stats.jarque_bera(times)
            return float(p), float(p) > 0.05
        except Exception:
            pass
    x = np.asarray(times)
    mean = np.mean(x)
    std = float(np.std(x, ddof=1))
    if std == 0:
        return 1.0, True
    skewness = float(np.sum(((x - mean) / std) ** 3) / n)
    kurtosis = float(np.sum(((x - mean) / std) ** 4) / n - 3)
    JB = (n / 6) * (skewness ** 2 + 0.25 * kurtosis ** 2)
    if SCIPY_AVAILABLE:
        try:
            p_value = float(1 - stats.chi2.cdf(JB, df=2))
        except Exception:
            p_value = math.exp(-JB / 2)
    else:
        p_value = math.exp(-JB / 2)
    return max(0.001, min(0.999, p_value)), p_value > 0.05


def cohen_d(times1: np.ndarray, times2: np.ndarray) -> float:
    """
    Cohen's d effect size between two samples.
    """
    n1, n2 = len(times1), len(times2)
    if n1 < 2 or n2 < 2:
        return 0.0
    mean1, mean2 = float(np.mean(times1)), float(np.mean(times2))
    var1, var2 = float(np.var(times1, ddof=1)), float(np.var(times2, ddof=1))
    pooled_std = np.sqrt(((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2))
    if pooled_std == 0:
        return 0.0
    return float((mean1 - mean2) / pooled_std)


def glass_delta(times1: np.ndarray, times2: np.ndarray) -> float:
    """
    Glass's Δ effect size. Uses control group (baseline) SD.
    """
    n1 = len(times1)
    if n1 < 2:
        return 0.0
    mean1, mean2 = float(np.mean(times1)), float(np.mean(times2))
    std1 = float(np.std(times1, ddof=1))
    if std1 == 0:
        return 0.0
    return float((mean2 - mean1) / std1)


def shapiro_wilk_test(times: np.ndarray) -> Tuple[float, bool]:
    """
    Shapiro-Wilk normality test.
    Returns p-value and whether distribution is normal (p > 0.05).
    """
    n = len(times)
    if n < 3 or n > 5000:
        return 1.0, True
    if SCIPY_AVAILABLE:
        try:
            stat, p = stats.shapiro(times)
            return float(p), float(p) > 0.05
        except Exception:
            pass
    # Fallback heuristic
    x = np.sort(times)
    mean = np.mean(x)
    std = float(np.std(x, ddof=1))
    if std > 0:
        skewness = abs(float(np.mean(((x - mean) / std) ** 3)))
        kurtosis_val = float(np.mean(((x - mean) / std) ** 4)) - 3
    else:
        skewness = 0
        kurtosis_val = 0
    is_normal = skewness < 2 and kurtosis_val < 7
    return 0.05 if is_normal else 0.01, is_normal


def bootstrap_ci(
    times: np.ndarray, n_bootstrap: int = 1000, ci: float = 0.95
) -> Tuple[float, float]:
    """
    Bootstrap confidence interval for minimum time.
    Returns (lower_bound, upper_bound) of the CI.
    """
    n = len(times)
    if n < 3:
        return float(np.min(times)), float(np.max(times))
    bootstrap_mins = np.zeros(n_bootstrap)
    for i in range(n_bootstrap):
        sample = np.random.choice(times, size=n, replace=True)
        bootstrap_mins[i] = np.min(sample)
    alpha = 1 - ci
    lower = float(np.percentile(bootstrap_mins, alpha / 2 * 100))
    upper = float(np.percentile(bootstrap_mins, (1 - alpha / 2) * 100))
    return lower, upper


def run_benchmark(
    func,
    runs: int = 30,
    warmup: int = 5,
    track_memory: bool = False,
    track_cpu: bool = False,
) -> Tuple[List[float], Optional[float], Optional[Dict]]:
    """
    Run a benchmark with proper methodology.
    Returns (times_list, peak_memory_mb, memory_details).
    """
    import time
    import tracemalloc
    for _ in range(warmup):
        func()
    times = []
    peak_memory_mb = None
    if track_memory:
        tracemalloc.start()
    try:
        for _ in range(runs):
            start = time.perf_counter()
            func()
            end = time.perf_counter()
            times.append(end - start)
            if track_memory:
                current, peak = tracemalloc.get_traced_memory()
                peak_memory_mb = peak / (1024 * 1024)
    finally:
        if track_memory:
            tracemalloc.stop()
    return times, peak_memory_mb, None


def bonferroni_correction(p_values: List[float], alpha: float = 0.05) -> List[bool]:
    """Bonferroni correction for multiple comparisons."""
    n = len(p_values)
    if n == 0:
        return []
    corrected_alpha = alpha / n
    return [p < corrected_alpha for p in p_values]


def benjamini_hochberg_correction(
    p_values: List[float], alpha: float = 0.05
) -> Tuple[List[bool], List[float]]:
    """Benjamini-Hochberg FDR correction."""
    n = len(p_values)
    if n == 0:
        return [], []
    sorted_indices = np.argsort(p_values)
    sorted_p = np.array(p_values)[sorted_indices]
    adjusted_p = np.zeros(n)
    for i in range(n - 1, -1, -1):
        rank = i + 1
        adjusted_p[i] = min(sorted_p[i] * n / rank, 1.0)
    for i in range(n - 2, -1, -1):
        adjusted_p[i] = min(adjusted_p[i], adjusted_p[i + 1])
    rejected = adjusted_p < alpha
    unrolled_rejected = [bool(rejected[idx]) for idx in np.argsort(sorted_indices)]
    unrolled_adjusted = [float(adjusted_p[idx]) for idx in np.argsort(sorted_indices)]
    return unrolled_rejected, unrolled_adjusted


def power_analysis_required_runs(
    effect_size: float,
    alpha: float = 0.05,
    power: float = 0.8,
    two_tailed: bool = True,
) -> int:
    """Calculate required sample size for desired power."""
    if effect_size <= 0:
        return 30
    try:
        from scipy import stats as scipy_stats
        z_alpha = scipy_stats.norm.ppf(1 - alpha / 2) if two_tailed else scipy_stats.norm.ppf(1 - alpha)
        z_beta = scipy_stats.norm.ppf(power)
    except ImportError:
        def normal_ppf(p):
            return math.sqrt(2) * math.erfinv(2 * p - 1)
        z_alpha = normal_ppf(1 - alpha / 2) if two_tailed else normal_ppf(1 - alpha)
        z_beta = normal_ppf(power)
    n = 2 * ((z_alpha + z_beta) / effect_size) ** 2
    return int(np.ceil(n))


def estimate_ci_width_required_runs(
    times: np.ndarray,
    target_width_pct: float = 0.05,
    confidence: float = 0.95,
) -> int:
    """Estimate required runs for a target CI width."""
    n = len(times)
    mean = float(np.mean(times))
    std = float(np.std(times, ddof=1))
    if mean == 0:
        return n
    se = std / np.sqrt(n)
    current_width = 2 * 1.96 * se
    current_width_pct = current_width / mean
    if current_width_pct <= target_width_pct:
        return n
    required_n = (2 * 1.96 * std / (target_width_pct * mean)) ** 2
    return int(np.ceil(required_n))


def detect_outliers_iqr(times: Union[np.ndarray, List[float]], factor: float = 1.5) -> Tuple[List[float], List[int]]:
    """Detect outliers using IQR method."""
    times_arr = np.asarray(times)
    q75, q25 = float(np.percentile(times_arr, 75)), float(np.percentile(times_arr, 25))
    iqr = q75 - q25
    lower = q25 - factor * iqr
    upper = q75 + factor * iqr
    mask = (times_arr >= lower) & (times_arr <= upper)
    outlier_indices = np.where(~mask)[0].tolist()
    filtered_list = times_arr[mask].tolist()
    return filtered_list, outlier_indices

# Backwards compatibility exports
hash_output = generate_hash
analyze_benchmark = run_benchmark

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