#!/usr/bin/env python3
"""
===============================================================================
SCENARIO A.2: Hyperspectral SAM – Python Implementation (Cuprite dataset)
===============================================================================
"""

import numpy as np
import scipy.io as sio
import sys
import json
import hashlib
from pathlib import Path

def spectral_angle_mapper(pixel_spectra, reference_spectrum):
    epsilon = 1e-8
    dot_product = np.dot(pixel_spectra, reference_spectrum)
    pixel_norms = np.linalg.norm(pixel_spectra, axis=1)
    ref_norm = np.linalg.norm(reference_spectrum)
    cos_angle = dot_product / (pixel_norms * ref_norm + epsilon)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    angles = np.arccos(cos_angle)
    return angles

def main():
    print("=" * 70)
    print("PYTHON - Scenario A.2: Hyperspectral SAM (Cuprite)")
    print("=" * 70)

    # -------------------------------------------------------------------------
    # 1. Load Cuprite dataset
    # -------------------------------------------------------------------------
    print("\n[1/5] Loading Cuprite dataset...")
    mat = sio.loadmat("data/Cuprite.mat")
    # Print available keys to identify the variable (optional, can be removed later)
    print("  ✓ MATLAB variables:", [k for k in mat.keys() if not k.startswith('__')])
    # The actual data variable is the long name; we'll use the first non‑metadata key
    data_key = [k for k in mat.keys() if not k.startswith('__')][0]
    data = mat[data_key]  # Expected shape: (bands, rows, cols)
    n_bands, n_rows, n_cols = data.shape
    print(f"  ✓ Dataset shape: {n_bands} bands, {n_rows}×{n_cols} pixels")

    # Generate reference spectrum (normalized)
    np.random.seed(42)
    reference_spectrum = np.random.rand(n_bands).astype(np.float32)
    reference_spectrum /= np.linalg.norm(reference_spectrum)
    print(f"  ✓ Reference spectrum hash: {hashlib.sha256(reference_spectrum.tobytes()).hexdigest()[:16]}")

    # -------------------------------------------------------------------------
    # 2. Process in chunks (same as before)
    # -------------------------------------------------------------------------
    print("\n[2/5] Processing hyperspectral data (chunked)...")
    chunk_size = 256
    sam_results = []
    pixels_processed = 0
    chunks_processed = 0

    for row in range(0, n_rows, chunk_size):
        for col in range(0, n_cols, chunk_size):
            r_end = min(row + chunk_size, n_rows)
            c_end = min(col + chunk_size, n_cols)
            chunk = data[:, row:r_end, col:c_end]
            pixel_spectra = chunk.reshape(n_bands, -1).T.astype(np.float32)
            sam_angles = spectral_angle_mapper(pixel_spectra, reference_spectrum)
            sam_results.extend(sam_angles.tolist())
            pixels_processed += pixel_spectra.shape[0]
            chunks_processed += 1
            if chunks_processed % 10 == 0:
                print(f"    Processed {chunks_processed} chunks ({pixels_processed:,} pixels)...", end='\r')

    print(f"    Processed {chunks_processed} chunks ({pixels_processed:,} pixels)... Done!")

    # -------------------------------------------------------------------------
    # 3. Statistics and validation (unchanged)
    # -------------------------------------------------------------------------
    print("\n[3/5] Computing statistics...")
    sam_array = np.array(sam_results)
    mean_sam = float(np.mean(sam_array))
    median_sam = float(np.median(sam_array))
    std_sam = float(np.std(sam_array))
    min_sam = float(np.min(sam_array))
    max_sam = float(np.max(sam_array))
    print(f"  ✓ Mean SAM: {mean_sam:.6f} rad ({np.degrees(mean_sam):.2f}°)")
    print(f"  ✓ Median SAM: {median_sam:.6f} rad")
    print(f"  ✓ Std Dev: {std_sam:.6f} rad")

    print("\n[4/5] Generating validation data...")
    result_str = f"{mean_sam:.8f}_{pixels_processed}_{median_sam:.8f}"
    result_hash = hashlib.sha256(result_str.encode()).hexdigest()[:16]
    print(f"  ✓ Validation hash: {result_hash}")

    results = {
        "language": "python",
        "scenario": "hyperspectral_sam",
        "pixels_processed": pixels_processed,
        "chunks_processed": chunks_processed,
        "n_bands": n_bands,
        "mean_sam_rad": mean_sam,
        "median_sam_rad": median_sam,
        "std_sam_rad": std_sam,
        "min_sam_rad": min_sam,
        "max_sam_rad": max_sam,
        "mean_sam_deg": float(np.degrees(mean_sam)),
        "validation_hash": result_hash,
        "reference_hash": hashlib.sha256(reference_spectrum.tobytes()).hexdigest()[:16]
    }

    Path("validation").mkdir(exist_ok=True)
    with open("validation/raster_python_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("\n  ✓ Results saved to validation/raster_python_results.json")
    print("=" * 70)
    return 0

if __name__ == "__main__":
    sys.exit(main())
