#!/usr/bin/env python3
"""
===============================================================================
SCENARIO A.2: Hyperspectral Spectral Angle Mapper - Python Implementation
==============================================================================
Task: SAM classification on 224-band hyperspectral imagery
Dataset: NASA AVIRIS Cuprite (224 bands, freely available)
Metrics: Memory striding efficiency, cache utilization, FLOPS
==============================================================================
"""
from pathlib import Path

import numpy as np
import scipy.io as sio
import sys
import json
import hashlib
import psutil
import os

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"





def spectral_angle_mapper(pixel_spectra, reference_spectrum):
    """
    Calculate Spectral Angle Mapper (SAM) between pixels and reference

    Args:
        pixel_spectra: Array of shape (n_pixels, n_bands)
        reference_spectrum: Array of shape (n_bands,)

    Returns:
        SAM angles in radians (array of shape n_pixels)
    """
    # Normalize to avoid numerical issues
    epsilon = 1e-8

    # Dot product: pixel · reference
    dot_product = np.dot(pixel_spectra, reference_spectrum)

    # Norms
    pixel_norms = np.linalg.norm(pixel_spectra, axis=1)
    ref_norm = np.linalg.norm(reference_spectrum)

    # Cosine of angle
    cos_angle = dot_product / (pixel_norms * ref_norm + epsilon)

    # Clip to valid range [-1, 1] to avoid numerical errors in arccos
    cos_angle = np.clip(cos_angle, -1.0, 1.0)

    # SAM angle (radians)
    angles = np.arccos(cos_angle)

    return angles


def main():
    print("=" * 70)
    print("PYTHON - Scenario A.2: Hyperspectral SAM")
    print("=" * 70)

    # =========================================================================
    # 1. Initialize
    # =========================================================================
    print("\n[1/5] Initializing...")

    # Deterministic reference spectrum (same across all languages)
    # Using linspace ensures identical values regardless of RNG
    n_bands = 224
    reference_spectrum = np.linspace(0.1, 0.9, n_bands).astype(np.float32)
    reference_spectrum /= np.linalg.norm(reference_spectrum)  # Normalize

    print(f"  ✓ Reference spectrum: {n_bands} bands")
    print(
        f"  ✓ Reference spectrum hash: {hashlib.sha256(reference_spectrum.tobytes()).hexdigest()[:16]}"
    )

    # =========================================================================
    # 2. Open Dataset (MAT file format)
    # =========================================================================
    print("\n[2/5] Opening hyperspectral dataset...")

    hsi_path = str(DATA_DIR / "Cuprite.mat")

    print(f"  ✓ Loading MAT file: {hsi_path}")
    mat = sio.loadmat(hsi_path)
    data_key = [k for k in mat.keys() if not k.startswith("__")][0]
    raw_data = mat[data_key]

    # Cuprite.mat has shape (512, 614, 224) = (rows, cols, bands)
    # R and Julia use permutedims/aperm to get (bands=224, rows=512, cols=614)
    # Fix Python to match R/Julia: use (2, 0, 1) to get (224, 512, 614)
    if raw_data.shape[2] == 224:
        data = raw_data.transpose(2, 0, 1)[:224, :, :]
        print(f"  ✓ Transposed data to (bands, rows, cols)")
    else:
        data = raw_data

    n_bands, n_rows, n_cols = data.shape
    print(f"  ✓ Dataset shape: {n_bands} bands × {n_rows} × {n_cols} pixels")

    file_size_gb = os.path.getsize(hsi_path) / (1024**3)
    print(f"  ✓ File size: {file_size_gb:.2f} GB")

    # Try to clear GDAL cache if available
    try:
        from osgeo import gdal
        gdal.VSICurlClearCache()
        print("  ✓ GDAL cache cleared")
    except ImportError:
        pass

    # Try to clear GDAL cache if available
    try:
        from osgeo import gdal
        gdal.PushErrorHandler('CPLQuietErrorHandler')
        gdal.VSICurlClearCache()
    except ImportError:
        pass

    available_ram = psutil.virtual_memory().available / (1024**3)
    print(f"  ✓ Available RAM: {available_ram:.2f} GB")
    if file_size_gb > available_ram * 0.8:
        print(
            f"  ⚠ Dataset size exceeds 80% of available RAM - using chunked processing"
        )

# =========================================================================
    # 3. Process in Chunks with STREAMING aggregation (memory efficient)
    # =========================================================================
    print("\n[3/5] Processing hyperspectral data (streaming, memory-efficient)...")

    chunk_size = 256

    # STREAMING: Accumulate incremental statistics instead of storing all results
    # This allows processing of arbitrarily large datasets without OOM
    sum_angles = 0.0
    sum_sq_angles = 0.0
    sum_min = float('inf')
    sum_max = float('-inf')
    count = 0
    pixels_processed = 0
    chunks_processed = 0

    for row in range(0, n_rows, chunk_size):
        for col in range(0, n_cols, chunk_size):
            row_end = min(row + chunk_size, n_rows)
            col_end = min(col + chunk_size, n_cols)

            chunk_data = data[:, row:row_end, col:col_end]
            chunk_pixels = chunk_data.shape[1] * chunk_data.shape[2]

            pixel_spectra = chunk_data.transpose(1, 2, 0).reshape(-1, n_bands)

            sam_angles = spectral_angle_mapper(pixel_spectra, reference_spectrum)

            # STREAMING AGGREGATION: Update running statistics
            chunk_sum = sam_angles.sum()
            chunk_sum_sq = (sam_angles ** 2).sum()
            sum_angles += chunk_sum
            sum_sq_angles += chunk_sum_sq
            sum_min = min(sum_min, sam_angles.min())
            sum_max = max(sum_max, sam_angles.max())
            count += len(sam_angles)
            pixels_processed += len(sam_angles)
            chunks_processed += 1

            if chunks_processed % 10 == 0:
                print(
                    f"    Processed {chunks_processed} chunks ({pixels_processed:,} pixels)...",
                    end="\r",
                )

    print(
        f"    Processed {chunks_processed} chunks ({pixels_processed:,} pixels)... Done!"
    )

    # Compute final statistics from streaming aggregates
    mean_angle = sum_angles / count if count > 0 else 0
    std_angle = np.sqrt(sum_sq_angles / count - mean_angle ** 2) if count > 0 else 0

    print(f"  ✓ Mean SAM angle: {mean_angle:.6f} rad")
    print(f"  ✓ Std SAM angle: {std_angle:.6f} rad")
    print(f"  ✓ Min SAM angle: {sum_min:.6f} rad")
    print(f"  ✓ Max SAM angle: {sum_max:.6f} rad")

    # Generate hash from streaming statistics (not all pixels - just aggregate)
    streaming_hash_input = f"{mean_angle:.8f},{std_angle:.8f},{sum_min:.8f},{sum_max:.8f}"
    validation_hash = hashlib.sha256(streaming_hash_input.encode()).hexdigest()[:16]
    print(f"  ✓ Validation hash: {validation_hash}")

    print(
        f"    Processed {chunks_processed} chunks ({pixels_processed:,} pixels)... Done!"
    )

    # =========================================================================
    # 4. Compute Statistics
    # =========================================================================
    print("\n[4/5] Computing statistics...")

    sam_array = np.array(sam_results)

    mean_sam = float(np.mean(sam_array))
    median_sam = float(np.median(sam_array))
    std_sam = float(np.std(sam_array))
    min_sam = float(np.min(sam_array))
    max_sam = float(np.max(sam_array))

    print(f"  ✓ Mean SAM: {mean_sam:.6f} radians ({np.degrees(mean_sam):.2f}°)")
    print(f"  ✓ Median SAM: {median_sam:.6f} radians")
    print(f"  ✓ Std Dev: {std_sam:.6f} radians")
    print(f"  ✓ Range: [{min_sam:.6f}, {max_sam:.6f}] radians")

    # =========================================================================
    # 5. Validation & Export
    # =========================================================================
    print("\n[5/5] Generating validation data...")

    # Generate validation hash
    result_str = f"{mean_sam:.8f}_{pixels_processed}_{median_sam:.8f}"
    result_hash = hashlib.sha256(result_str.encode()).hexdigest()[:16]

    print(f"  ✓ Validation hash: {result_hash}")

    # Export results
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
        "reference_hash": hashlib.sha256(reference_spectrum.tobytes()).hexdigest()[:16],
    }

    # Save results
    output_dir = Path("validation")
    output_dir.mkdir(exist_ok=True)

    with open(output_dir / "raster_python_results.json", "w") as f:
        json.dump(results, f, indent=2)

    print(f"\n  ✓ Results saved to validation/raster_python_results.json")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())