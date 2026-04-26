#!/usr/bin/env python3
"""
SCENARIO E: NDVI Time-Series - Python Implementation
Tests: Temporal aggregation, trend analysis (OLS), and multi-band processing
"""
from pathlib import Path

import numpy as np
import time
import json
import hashlib
import os

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"





def generate_synthetic_ndvi_stack(n_dates=12, height=500, width=500):
    """Generate synthetic NDVI data with RED/NIR bands then compute actual NDVI
    
    This matches R and Julia implementations which generate red/nir bands
    then compute NDVI = (nir - red) / (nir + red)
    """
    np.random.seed(42)
    
    # Base vegetation pattern spatial distribution
    x = np.linspace(-1, 1, width)
    y = np.linspace(-1, 1, height)
    xx, yy = np.meshgrid(x, y)
    base_vegetation = 0.5 * (1 - (xx**2 + yy**2))
    
    # Generate RED and NIR bands separately (then compute NDVI)
    red_bands = np.zeros((n_dates, height, width), dtype=np.float32)
    nir_bands = np.zeros((n_dates, height, width), dtype=np.float32)
    
    for t in range(n_dates):
        # Seasonal cycle - vegetation_level as in R/Julia
        vegetation_level = 0.5 + 0.3 * np.sin(2 * np.pi * t / n_dates)
        noise = np.random.normal(0, 0.05, (height, width))
        
        # RED band: vegetation reduces red reflectance (uses vegetation_level)
        red_bands[t] = (0.1 + 0.2 * (1 - base_vegetation * vegetation_level) + noise).astype(np.float32)
        
        # NIR band: vegetation increases NIR reflectance  
        nir_bands[t] = (0.3 + 0.5 * base_vegetation * vegetation_level + noise).astype(np.float32)
    
    # Compute actual NDVI from red/nir bands: NDVI = (nir - red) / (nir + red + epsilon)
    epsilon = 1e-6
    ndvi_stack = ((nir_bands - red_bands) / (nir_bands + red_bands + epsilon)).astype(np.float32)
    ndvi_stack = np.clip(ndvi_stack, -0.1, 1.0)
        
    return ndvi_stack


def calculate_ndvi_statistics(ndvi_stack):
    """Perform temporal aggregation and trend analysis"""
    n_dates, height, width = ndvi_stack.shape
    
    # 1. Temporal Aggregation (Mean, Max, Min)
    mean_ndvi = np.mean(ndvi_stack, axis=0)
    max_ndvi = np.max(ndvi_stack, axis=0)
    min_ndvi = np.min(ndvi_stack, axis=0)
    
    # 2. Linear Trend Analysis (OLS slope)
    time_index = np.arange(n_dates).astype(np.float32)
    mean_time = np.mean(time_index)
    
    # Pre-calculate denominator (constant for all pixels)
    denominator = np.sum((time_index - mean_time)**2)
    
    # Vectorized OLS: (sum((x-mx)*(y-my))) / sum((x-mx)^2)
    numerator = np.sum((time_index[:, None, None] - mean_time) * (ndvi_stack - mean_ndvi), axis=0)
    ndvi_trend = numerator / denominator
    
    # 3. Phenology: Growing Season Length (NDVI > 0.3)
    growing_season = np.sum(ndvi_stack > 0.3, axis=0)
    
    # 4. Phenology: Amplitude
    amplitude = max_ndvi - min_ndvi
    
    return mean_ndvi, ndvi_trend, amplitude


def main():
    print("=" * 70)
    print("PYTHON - Scenario E: NDVI Time-Series")
    print("=" * 70)
    
    # 1. Generate/Load Data
    print("\n[1/4] Generating synthetic NDVI stack...")
    n_dates, height, width = 12, 500, 500
    ndvi_stack = generate_synthetic_ndvi_stack(n_dates, height, width)
    print(f"  ✓ Stack shape: {n_dates} dates × {height} × {width} pixels")
    
    # 2. Run Benchmark
    print("\n[2/4] Running NDVI time-series analysis...")
    
    # Warmup
    calculate_ndvi_statistics(ndvi_stack[:5])
    
    t_start = time.time()
    mean_ndvi, ndvi_trend, amplitude = calculate_ndvi_statistics(ndvi_stack)
    t_end = time.time()
    
    duration = t_end - t_start
    print(f"  ✓ Completed in {duration:.4f} seconds")
    
    # 3. Hash and Export
    # Combine results for hashing
    result_hash = hashlib.sha256(
        np.array([mean_ndvi.mean(), ndvi_trend.mean(), amplitude.mean()], dtype=np.float32).tobytes()
    ).hexdigest()[:16]
    
    print(f"  ✓ Validation hash: {result_hash}")
    
    output = {
        "language": "python",
        "scenario": "timeseries_ndvi",
        "min_time_s": duration,
        "n_dates": n_dates,
        "hash": result_hash
    }
    
    Path("results").mkdir(exist_ok=True)
    with open("results/timeseries_ndvi_python.json", "w") as f:
        json.dump(output, f, indent=2)
    print("✓ Results saved to results/timeseries_ndvi_python.json")


if __name__ == "__main__":
    main()