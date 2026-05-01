#!/usr/bin/env python3
"""
Generate synthetic datasets for reproducible benchmarking.

This ensures that all languages process identical data, eliminating PRNG 
differences as a source of variance.
"""

import numpy as np
import csv
from pathlib import Path

def generate_synthetic_ndvi(seed=42):
    """Generate synthetic NDVI data with deterministic red/nir bands."""
    print("Generating synthetic NDVI data...")
    
    np.random.seed(seed)
    n_pixels = 1000000  # 1M pixels
    
    # Generate deterministic red and nir bands
    red_band = np.random.normal(0.3, 0.1, n_pixels).clip(0.0, 1.0)
    nir_band = np.random.normal(0.7, 0.15, n_pixels).clip(0.0, 1.0)
    
    # Save as .npy files for direct loading
    output_dir = Path("data/synthetic")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    np.save(output_dir / "ndvi_red_band.npy", red_band)
    np.save(output_dir / "ndvi_nir_band.npy", nir_band)
    
    print(f"  ✓ Saved red/nir bands to {output_dir}")

def generate_synthetic_idw_points(seed=42):
    """Generate synthetic points for IDW interpolation."""
    print("Generating synthetic IDW points...")
    
    np.random.seed(seed)
    n_points = 100000  # 100K points
    
    # Generate deterministic point coordinates and values
    lons = np.random.uniform(-180, 180, n_points)
    lats = np.random.uniform(-90, 90, n_points)
    values = np.random.normal(25.0, 10.0, n_points)
    
    # Save as CSV for easy loading
    output_dir = Path("data/synthetic")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    csv_path = output_dir / "idw_points.csv"
    with open(csv_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['longitude', 'latitude', 'value'])
        for i in range(n_points):
            writer.writerow([lons[i], lats[i], values[i]])
    
    print(f"  ✓ Saved IDW points to {csv_path}")

def main():
    """Generate all synthetic datasets."""
    print("=" * 60)
    print("GENERATING SYNTHETIC DATASETS FOR CONSISTENT BENCHMARKING")
    print("=" * 60)
    
    generate_synthetic_ndvi()
    generate_synthetic_idw_points()
    
    print("\n✓ All synthetic datasets generated successfully!")

if __name__ == "__main__":
    main()