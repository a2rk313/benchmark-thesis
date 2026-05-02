"""
Core Statistics Utilities for Cross-Language Benchmarking
Provides consistent statistical methods matching Julia/R implementations.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

import math
import statistics
import hashlib
import json
import numpy as np
from typing import Union, List, Dict, Any

def median_of_means(data: List[float], block_size: int = 5) -> float:
    """
    Median-of-Means estimator: robust to outliers.
    Split data into blocks, compute mean of each block, return median of means.
    """
    n = len(data)
    if n < block_size:
        return statistics.mean(data)
    
    n_blocks = math.ceil(n / block_size)
    blocks = []
    for i in range(n_blocks):
        start = i * block_size
        end = min(start + block_size, n)
        blocks.append(statistics.mean(data[start:end]))
    return statistics.median(blocks)


def round_val(v: Any, precision: int = 6) -> Any:
    """
    Round value to specified precision, converting numpy types to Python types.
    """
    if isinstance(v, (np.integer, np.int32, np.int64)):
        return int(v)
    if isinstance(v, (np.floating, np.float32, np.float64)):
        return round(float(v), precision)
    if isinstance(v, (np.ndarray, list)):
        return [round_val(x) for x in v]
    if isinstance(v, dict):
        return {k: round_val(v) for k, v in v.items()}
    if isinstance(v, (int, float)):
        return round(float(v), precision)
    return v


# Re-export generate_hash from common_hash.py (consistent with Julia)
from common_hash import generate_hash


# Re-export functions from benchmark_stats.py for backwards compatibility
# These were missing and causing ImportError in multiple files
try:
    from benchmark_stats import (
        shapiro_wilk_test,
        bootstrap_ci,
        run_benchmark,
        dagostino_pearson_test,
        jarque_bera_test,
        cohen_d,
        glass_delta,
        bonferroni_correction,
        benjamini_hochberg_correction,
        power_analysis_required_runs,
        estimate_ci_width_required_runs,
        detect_outliers_iqr,
    )
except ImportError:
    # If benchmark_stats not available, functions won't be re-exported
    pass
