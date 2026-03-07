#!/usr/bin/env python3
"""
===============================================================================
SCENARIO D: Time-Series NDVI Analysis - Python Implementation
===============================================================================
Task: Calculate NDVI statistics across 12-month time series
Dataset: Synthetic Landsat-like data (500x500 pixels × 12 dates × 2 bands)
         Total size: ~24 MB (fits in RAM, avoids disk issues)
Metrics: Temporal aggregation, statistical computation, memory efficiency
===============================================================================
"""

import numpy as np
import json
import hashlib
from pathlib import Path
import time

def generate_synthetic_landsat(width=500, height=500, n_dates=12, seed=42):
    """
    Generate synthetic Landsat-like time series
    
    Returns:
        red_bands: (n_dates, height, width) - Red band values
        nir_bands: (n_dates, height, width) - NIR band values
    """
    np.random.seed(seed)
    
    # Create spatial patterns
    x = np.linspace(0, 4*np.pi, width)
    y = np.linspace(0, 4*np.pi, height)
    X, Y = np.meshgrid(x, y)
    
    # Base vegetation pattern
    base_vegetation = (np.sin(X) * np.cos(Y) + 1) / 2  # [0, 1]
    
    # Generate time series
    red_bands = np.zeros((n_dates, height, width), dtype=np.float32)
    nir_bands = np.zeros((n_dates, height, width), dtype=np.float32)
    
    for t in range(n_dates):
        # Seasonal variation (growing season)
        season_factor = np.sin(2 * np.pi * t / 12)  # -1 to 1
        vegetation_level = 0.5 + 0.3 * season_factor  # 0.2 to 0.8
        
        # Red band (lower in vegetation)
        red_bands[t] = (
            0.1 + 0.2 * (1 - base_vegetation * vegetation_level) +
            0.05 * np.random.randn(height, width)
        )
        
        # NIR band (higher in vegetation)
        nir_bands[t] = (
            0.3 + 0.5 * base_vegetation * vegetation_level +
            0.05 * np.random.randn(height, width)
        )
    
    # Clip to valid range [0, 1]
    red_bands = np.clip(red_bands, 0, 1)
    nir_bands = np.clip(nir_bands, 0, 1)
    
    return red_bands, nir_bands

def calculate_ndvi(red, nir):
    """
    Calculate NDVI = (NIR - Red) / (NIR + Red)
    """
    epsilon = 1e-8
    ndvi = (nir - red) / (nir + red + epsilon)
    return np.clip(ndvi, -1, 1)

def main():
    print("=" * 70)
    print("PYTHON - Scenario D: Time-Series NDVI Analysis")
    print("=" * 70)
    
    # =========================================================================
    # 1. Generate synthetic time series data
    # =========================================================================
    print("\n[1/5] Generating synthetic Landsat time series...")
    
    width, height = 500, 500
    n_dates = 12  # Monthly for 1 year
    
    start_time = time.time()
    red_bands, nir_bands = generate_synthetic_landsat(width, height, n_dates)
    gen_time = time.time() - start_time
    
    data_size_mb = (red_bands.nbytes + nir_bands.nbytes) / (1024**2)
    
    print(f"  ✓ Generated {n_dates} dates of {width}×{height} imagery")
    print(f"  ✓ Data size: {data_size_mb:.1f} MB")
    print(f"  ✓ Generation time: {gen_time:.2f} seconds")
    
    # =========================================================================
    # 2. Calculate NDVI for each date
    # =========================================================================
    print("\n[2/5] Calculating NDVI for each date...")
    
    start_time = time.time()
    ndvi_stack = np.zeros((n_dates, height, width), dtype=np.float32)
    
    for t in range(n_dates):
        ndvi_stack[t] = calculate_ndvi(red_bands[t], nir_bands[t])
    
    calc_time = time.time() - start_time
    
    print(f"  ✓ NDVI calculated for all {n_dates} dates")
    print(f"  ✓ Calculation time: {calc_time:.2f} seconds")
    print(f"  ✓ NDVI range: [{ndvi_stack.min():.3f}, {ndvi_stack.max():.3f}]")
    
    # =========================================================================
    # 3. Temporal statistics
    # =========================================================================
    print("\n[3/5] Computing temporal statistics...")
    
    start_time = time.time()
    
    # Pixel-wise temporal statistics
    mean_ndvi = np.mean(ndvi_stack, axis=0)
    std_ndvi = np.std(ndvi_stack, axis=0)
    max_ndvi = np.max(ndvi_stack, axis=0)
    min_ndvi = np.min(ndvi_stack, axis=0)
    
    # Trend detection (simple linear regression slope)
    time_index = np.arange(n_dates).reshape(-1, 1, 1)
    
    # Vectorized linear regression
    mean_time = time_index.mean()
    mean_ndvi_time = ndvi_stack.mean(axis=0)
    
    numerator = ((time_index - mean_time) * (ndvi_stack - mean_ndvi_time)).sum(axis=0)
    denominator = ((time_index - mean_time) ** 2).sum()
    
    ndvi_trend = numerator / denominator
    
    stats_time = time.time() - start_time
    
    print(f"  ✓ Temporal statistics computed")
    print(f"  ✓ Computation time: {stats_time:.2f} seconds")
    print(f"  ✓ Mean NDVI (spatial avg): {mean_ndvi.mean():.3f}")
    print(f"  ✓ Average trend: {ndvi_trend.mean():.6f} NDVI/month")
    
    # =========================================================================
    # 4. Phenology metrics
    # =========================================================================
    print("\n[4/5] Extracting phenology metrics...")
    
    start_time = time.time()
    
    # Find peak vegetation month for each pixel
    peak_month = np.argmax(ndvi_stack, axis=0)
    
    # Calculate growing season length (months above threshold)
    threshold = 0.3
    growing_season = (ndvi_stack > threshold).sum(axis=0)
    
    # Calculate seasonal amplitude
    amplitude = max_ndvi - min_ndvi
    
    pheno_time = time.time() - start_time
    
    print(f"  ✓ Phenology metrics extracted")
    print(f"  ✓ Computation time: {pheno_time:.2f} seconds")
    print(f"  ✓ Average peak month: {peak_month.mean():.1f}")
    print(f"  ✓ Average growing season: {growing_season.mean():.1f} months")
    print(f"  ✓ Average amplitude: {amplitude.mean():.3f}")
    
    # =========================================================================
    # 5. Results and validation
    # =========================================================================
    print("\n[5/5] Computing final metrics...")
    
    total_time = calc_time + stats_time + pheno_time
    pixels_processed = width * height * n_dates
    throughput = pixels_processed / total_time
    
    print(f"  ✓ Total processing time: {total_time:.2f} seconds")
    print(f"  ✓ Throughput: {throughput:,.0f} pixel-dates/second")
    
    # Generate validation hash
    result_str = f"{mean_ndvi.mean():.6f}_{ndvi_trend.mean():.6f}_{amplitude.mean():.6f}"
    result_hash = hashlib.sha256(result_str.encode()).hexdigest()[:16]
    
    print(f"  ✓ Validation hash: {result_hash}")
    
    # Export results
    results = {
        "language": "python",
        "scenario": "timeseries_ndvi",
        "image_size": f"{width}x{height}",
        "n_dates": n_dates,
        "total_pixels_processed": pixels_processed,
        "execution_time_s": total_time,
        "throughput_pixels_per_sec": throughput,
        "mean_ndvi": float(mean_ndvi.mean()),
        "mean_trend": float(ndvi_trend.mean()),
        "mean_amplitude": float(amplitude.mean()),
        "avg_growing_season": float(growing_season.mean()),
        "validation_hash": result_hash
    }
    
    # Save results
    output_dir = Path("validation")
    output_dir.mkdir(exist_ok=True)
    
    with open(output_dir / "timeseries_python_results.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n  ✓ Results saved to validation/timeseries_python_results.json")
    print("=" * 70)
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
