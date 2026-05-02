#!/usr/bin/env python3
"""
SCENARIO A.2: Hyperspectral Spectral Angle Mapper - Python Implementation
Task: SAM classification on 224-band hyperspectral imagery
Dataset: NASA AVIRIS Cuprite (224 bands) or synthetic fallback
Metrics: Memory striding efficiency, cache utilization, FLOPS
"""
from pathlib import Path

import argparse
import numpy as np
import scipy.io as sio
import sys
import json
import hashlib
import psutil
import os
import time

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import generate_hash

PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
OUTPUT_DIR = Path(__file__).parent.parent / "results"
VALIDATION_DIR = Path(__file__).parent.parent / "validation"

RUNS = 5
WARMUP = 2


def load_synthetic_hsi(n_bands=224, n_rows=512, n_cols=614):
    """Generate synthetic hyperspectral data matching Cuprite.mat shape."""
    print("  Generating synthetic HSI data...")
    np.random.seed(42)

    x = np.linspace(0, 4 * np.pi, n_cols)
    y = np.linspace(0, 4 * np.pi, n_rows)
    xx, yy = np.meshgrid(x, y)

    signal = 0.3 * np.sin(xx + yy) + 0.2 * np.sin(2 * xx - yy)

    data = np.zeros((n_bands, n_rows, n_cols), dtype=np.float32)
    spectral_pattern = np.linspace(0.8, 1.2, n_bands)

    for b in range(n_bands):
        noise = np.random.randn(n_rows, n_cols) * 100
        data[b] = ((signal + noise) * spectral_pattern[b] * 100 + 1000).astype(
            np.float32
        )

    print(f"  + Synthetic HSI: {n_bands} bands × {n_rows} × {n_cols}")
    return data


def load_data(data_mode):
    """Load HSI data based on mode: auto (real→synthetic), real, or synthetic."""
    if data_mode == "synthetic":
        return load_synthetic_hsi(), "synthetic"

    hsi_path = str(DATA_DIR / "Cuprite.mat")
    if os.path.exists(hsi_path) or data_mode == "real":
        try:
            print(f"  Loading MAT file: {hsi_path}")
            mat = sio.loadmat(hsi_path)
            data_key = [k for k in mat.keys() if not k.startswith("__")][0]
            raw_data = mat[data_key]

            if raw_data.shape[2] == 224:
                data = raw_data.transpose(2, 0, 1)[:224, :, :]
            else:
                data = raw_data

            print(f"  + Real HSI: {data.shape[0]} bands × {data.shape[1]} × {data.shape[2]}")
            return data, "real"
        except Exception as e:
            if data_mode == "real":
                print(f"  x Real data load failed: {e}")
                sys.exit(1)
            print(f"  - Real data unavailable ({e}), using synthetic")

    return load_synthetic_hsi(), "synthetic"


def spectral_angle_mapper(pixel_spectra, reference_spectrum):
    epsilon = 1e-8
    dot_product = np.dot(pixel_spectra, reference_spectrum)
    pixel_norms = np.linalg.norm(pixel_spectra, axis=1)
    ref_norm = np.linalg.norm(reference_spectrum)
    cos_angle = dot_product / (pixel_norms * ref_norm + epsilon)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    angles = np.arccos(cos_angle)
    return angles


def process_chunked(data, reference_spectrum, chunk_size=256):
    n_bands, n_rows, n_cols = data.shape
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
            pixel_spectra = chunk_data.transpose(1, 2, 0).reshape(-1, n_bands)
            sam_angles = spectral_angle_mapper(pixel_spectra, reference_spectrum)
            chunk_sum = sam_angles.sum()
            chunk_sum_sq = (sam_angles ** 2).sum()
            sum_angles += chunk_sum
            sum_sq_angles += chunk_sum_sq
            sum_min = min(sum_min, sam_angles.min())
            sum_max = max(sum_max, sam_angles.max())
            count += len(sam_angles)
            pixels_processed += len(sam_angles)
            chunks_processed += 1

    mean_angle = sum_angles / count if count > 0 else 0
    std_angle = np.sqrt(sum_sq_angles / count - mean_angle ** 2) if count > 0 else 0
    # Note: Streaming computation reports mean (not true median).
    # True median would require storing all angles in memory.
    # This is a documented streaming limitation — mean is reported
    # as the central tendency metric for SAM classification results.
    return mean_angle, std_angle, sum_min, sum_max, pixels_processed, chunks_processed


def main():
    parser = argparse.ArgumentParser(description="Hyperspectral SAM Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    args = parser.parse_args()

    print("=" * 70)
    print("PYTHON - Scenario A.2: Hyperspectral SAM")
    print("=" * 70)

    print("\n[1/5] Initializing...")
    n_bands = 224
    reference_spectrum = np.linspace(0.1, 0.9, n_bands).astype(np.float32)
    reference_spectrum /= np.linalg.norm(reference_spectrum)
    print(f"  + Reference spectrum: {n_bands} bands")

    print("\n[2/5] Opening hyperspectral dataset...")
    data, data_source = load_data(args.data)

    n_bands, n_rows, n_cols = data.shape
    print(f"  + Dataset shape: {n_bands} bands × {n_rows} × {n_cols} pixels")

    available_ram = psutil.virtual_memory().available / (1024**3)
    print(f"  + Available RAM: {available_ram:.2f} GB")

    print(f"\n[3/5] Running SAM classification ({RUNS} runs, {WARMUP} warmup)...")

    def task():
        return process_chunked(data, reference_spectrum)

    for _ in range(WARMUP):
        task()

    times = []
    result = None
    for i in range(RUNS):
        t_start = time.perf_counter()
        result = task()
        t_end = time.perf_counter()
        times.append(t_end - t_start)
        if i == 0:
            mean_angle, std_angle, sum_min, sum_max, pixels_processed, chunks_processed = result

    print(f"  ✓ Min: {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")

    print("\n[4/5] SAM classification results...")
    print(f"  ✓ Mean SAM angle: {mean_angle:.6f} rad ({np.degrees(mean_angle):.2f}°)")
    print(f"  ✓ Std SAM angle: {std_angle:.6f} rad")
    print(f"  ✓ Min SAM angle: {sum_min:.6f} rad")
    print(f"  ✓ Max SAM angle: {sum_max:.6f} rad")
    print(f"  ✓ Processed {chunks_processed} chunks ({pixels_processed:,} pixels)")

    print("\n[5/5] Validation and export...")
    hash_input = np.array([mean_angle, std_angle, sum_min, sum_max], dtype=np.float64)
    validation_hash = generate_hash(hash_input)
    print(f"  ✓ Validation hash: {validation_hash}")

    results = {
        "language": "python",
        "scenario": "hyperspectral_sam",
        "data_source": data_source,
        "data_description": "Cuprite.mat" if data_source == "real" else f"synthetic {n_bands}x{n_rows}x{n_cols}",
        "pixels_processed": pixels_processed,
        "chunks_processed": chunks_processed,
        "n_bands": n_bands,
        "mean_sam_rad": float(mean_angle),
        "std_sam_rad": float(std_angle),
        "min_sam_rad": float(sum_min),
        "max_sam_rad": float(sum_max),
        "mean_sam_deg": float(np.degrees(mean_angle)),
        "min_time_s": min(times),
        "mean_time_s": float(np.mean(times)),
        "std_time_s": float(np.std(times, ddof=1)),
        "median_time_s": float(np.median(times)),
        "max_time_s": max(times),
        "times": times,
        "validation_hash": validation_hash,
        "reference_hash": hashlib.sha256(reference_spectrum.tobytes()).hexdigest()[:16],
    }

    OUTPUT_DIR.mkdir(exist_ok=True)
    VALIDATION_DIR.mkdir(exist_ok=True)
    with open(OUTPUT_DIR / "hsi_stream_python.json", "w") as f:
        json.dump(results, f, indent=2)
    with open(VALIDATION_DIR / "raster_python_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("✓ Results saved")
    print("=" * 70)


if __name__ == "__main__":
    main()
