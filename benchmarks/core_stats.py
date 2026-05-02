"""
Core Statistics Utilities for Cross-Language Benchmarking
Provides consistent statistical methods matching Julia/R implementations.
"""

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


def sample_array(arr: Union[np.ndarray, List], n_samples: int = 100) -> List:
    """
    Sample array consistently to match Julia/Python/R implementations.
    Uses round() instead of floor() for cross-language sync.
    """
    flat = list(arr) if isinstance(arr, np.ndarray) else arr
    n = len(flat)
    if n <= n_samples:
        return flat
    indices = np.round(np.linspace(0, n-1, n_samples)).astype(int)
    return [flat[i] for i in indices]


def generate_hash(data: Union[np.ndarray, Dict, List], n_samples: int = 100) -> str:
    """
    Generate consistent hash across languages using SHA256 + sampling.
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
            val = round_val(data[0]) if len(data) > 0 else 0
            content = json.dumps(val, separators=(',', ':')) if JSON_AVAILABLE else str(val)
    else:
        content = json.dumps(round_val(data), separators=(',', ':')) if JSON_AVAILABLE else str(round_val(data))
    
    return hashlib.sha256(content.encode()).hexdigest()[:16]
