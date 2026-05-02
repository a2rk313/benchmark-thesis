#!/usr/bin/env python3
"""
Extract real MODIS NDVI time-series from HDF file.

Usage:
    python tools/extract_modis_ndvi.py                  # Extract from HDF if available, else synthetic
    python tools/extract_modis_ndvi.py --real-only      # Extract from HDF only (fail if unavailable)
    python tools/extract_modis_ndvi.py --synthetic      # Generate synthetic only
    python tools/extract_modis_ndvi.py --size xlarge    # Synthetic at 1200x1200

Output: data/modis/modis_ndvi_real.bin (ENVI format, float32)
        data/modis/modis_ndvi_real.hdr (ENVI header)

The real MODIS MOD13A1 NDVI values are stored as 16-bit integers with scale factor 0.0001.
This script extracts and converts to float32 NDVI values (-0.1 to 1.0).
"""

import argparse
import sys
from pathlib import Path

import numpy as np

SCRIPT_DIR = Path(__file__).parent.parent
DATA_DIR = SCRIPT_DIR / "data" / "modis"

NDVI_SCALE = 0.0001
NDVI_FILL = -3000


def extract_from_hdf(hdf_path: Path, output_bin: Path, output_hdr: Path) -> bool:
    """Extract NDVI bands from MODIS HDF-EOS file using GDAL."""
    try:
        from osgeo import gdal
    except ImportError:
        print("  - GDAL (osgeo) not available")
        return False

    print(f"  Extracting NDVI from: {hdf_path.name}")

    ds = gdal.Open(str(hdf_path))
    if ds is None:
        print("  x Failed to open HDF file with GDAL")
        return False

    n_bands = ds.RasterCount
    width = ds.RasterXSize
    height = ds.RasterYSize
    print(f"  + Opened HDF: {n_bands} bands, {width}x{height}")

    subdatasets = ds.GetMetadata("SUBDATASETS")
    ndvi_data = []

    if subdatasets:
        ndvi_keys = [k for k in subdatasets
                     if "NDVI" in str(subdatasets[k]).upper()
                     and "16_DAYS" in str(subdatasets[k]).upper()]
        if ndvi_keys:
            sd_path = subdatasets[ndvi_keys[0]]
            print(f"  + Found NDVI subdataset")
            ndvi_ds = gdal.Open(sd_path)
            if ndvi_ds:
                for b in range(1, ndvi_ds.RasterCount + 1):
                    band = ndvi_ds.GetRasterBand(b)
                    raw = band.ReadAsArray().astype(np.float32)
                    raw = np.where(raw == NDVI_FILL, np.nan,
                                   raw * NDVI_SCALE)
                    raw = np.clip(raw, -0.1, 1.0)
                    ndvi_data.append(raw)
                ndvi_ds = None
        else:
            print("  - No NDVI subdataset found, trying all bands")
            for b in range(1, min(n_bands + 1, 25)):
                band = ds.GetRasterBand(b)
                raw = band.ReadAsArray().astype(np.float32)
                raw = np.where(raw == NDVI_FILL, np.nan,
                               raw * NDVI_SCALE)
                raw = np.clip(raw, -0.1, 1.0)
                ndvi_data.append(raw)
    else:
        for b in range(1, min(n_bands + 1, 25)):
            band = ds.GetRasterBand(b)
            raw = band.ReadAsArray().astype(np.float32)
            raw = np.where(raw == NDVI_FILL, np.nan, raw * NDVI_SCALE)
            raw = np.clip(raw, -0.1, 1.0)
            ndvi_data.append(raw)

    ds = None

    if not ndvi_data:
        print("  x No NDVI data extracted")
        return False

    data = np.stack(ndvi_data, axis=0).astype(np.float32)
    n_bands_out, rows, cols = data.shape
    print(f"  + Extracted {n_bands_out} NDVI bands: {rows}x{cols}")

    output_bin.parent.mkdir(parents=True, exist_ok=True)
    data.tofile(output_bin)

    hdr_content = f"""ENVI
samples = {cols}
lines = {rows}
bands = {n_bands_out}
header offset = 0
file type = ENVI Standard
data type = 4
interleave = bil
description = MODIS NDVI 16-day composite time series (real data, extracted from HDF)
map info = {{Geographic Lat/Lon, 1, 1, -180.0, 90.0, 0.0083333, 0.0083333, WGS-84, units=degrees}}
"""
    output_hdr.write_text(hdr_content)

    size_mb = output_bin.stat().st_size / 1024 / 1024
    print(f"  + Saved: {output_bin} ({size_mb:.1f} MB)")
    print(f"  + Header: {output_hdr}")

    return True


def generate_synthetic(output_bin: Path, output_hdr: Path,
                       n_bands: int = 46, n_rows: int = 500, n_cols: int = 500) -> bool:
    """Generate synthetic MODIS-like NDVI time series."""
    print(f"  Generating synthetic MODIS NDVI ({n_bands} dates x {n_rows}x{n_cols})")

    np.random.seed(42)

    x = np.linspace(-1, 1, n_cols)
    y = np.linspace(-1, 1, n_rows)
    xx, yy = np.meshgrid(x, y)

    vegetation_base = np.exp(-(xx**2 + yy**2) / 0.5)
    vegetation_base += 0.3 * np.sin(xx * 3) * np.cos(yy * 2)
    vegetation_base = np.clip(vegetation_base, 0, 1)

    t = np.linspace(0, 4 * np.pi, n_bands)
    seasonal = (np.sin(t) + 1) / 2

    ndvi_data = np.zeros((n_bands, n_rows, n_cols), dtype=np.float32)
    for i in range(n_bands):
        vegetation = vegetation_base * (0.3 + 0.5 * seasonal[i])
        noise = np.random.randn(n_rows, n_cols) * 0.05
        ndvi_data[i] = np.clip(vegetation + noise, -0.1, 1.0)

    output_bin.parent.mkdir(parents=True, exist_ok=True)
    ndvi_data.tofile(output_bin)

    hdr_content = f"""ENVI
samples = {n_cols}
lines = {n_rows}
bands = {n_bands}
header offset = 0
file type = ENVI Standard
data type = 4
interleave = bil
description = MODIS NDVI 16-day composite time series (synthetic, seed=42)
map info = {{Geographic Lat/Lon, 1, 1, -180.0, 90.0, 0.0083333, 0.0083333, WGS-84, units=degrees}}
"""
    output_hdr.write_text(hdr_content)

    size_mb = output_bin.stat().st_size / 1024 / 1024
    print(f"  + Saved: {output_bin} ({size_mb:.1f} MB)")

    return True


def main():
    parser = argparse.ArgumentParser(description="Extract MODIS NDVI time-series from HDF")
    parser.add_argument("--real-only", action="store_true",
                       help="Extract from HDF only (fail if unavailable)")
    parser.add_argument("--synthetic", action="store_true",
                       help="Generate synthetic data only")
    parser.add_argument("--hdf-path", type=str,
                       help="Path to MODIS HDF file (default: auto-detect)")
    parser.add_argument("--size", choices=["small", "large", "xlarge"],
                       default="large",
                       help="Size for synthetic: small=100x100, large=500x500, xlarge=1200x1200")
    args = parser.parse_args()

    print("=" * 60)
    print("MODIS NDVI TIME-SERIES DATA EXTRACTOR")
    print("=" * 60)

    hdf_path = Path(args.hdf_path) if args.hdf_path else None
    if hdf_path is None:
        for candidate in [
            DATA_DIR / "MOD13A1.A2026081.h12v04.061.2026097235932.hdf",
            DATA_DIR / "MOD13A1.hdf",
        ]:
            if candidate.exists():
                hdf_path = candidate
                break

    output_bin = DATA_DIR / "modis_ndvi_real.bin"
    output_hdr = DATA_DIR / "modis_ndvi_real.hdr"

    if args.real_only:
        if hdf_path is None or not hdf_path.exists():
            print(f"  x HDF file not found: {hdf_path}")
            sys.exit(1)
        if not extract_from_hdf(hdf_path, output_bin, output_hdr):
            print("  x Extraction failed")
            sys.exit(1)
        print("  + Real NDVI extraction complete")
        return 0

    if args.synthetic:
        sizes = {"small": (46, 100, 100), "large": (46, 500, 500), "xlarge": (46, 1200, 1200)}
        n_b, n_r, n_c = sizes[args.size]
        generate_synthetic(output_bin, output_hdr, n_b, n_r, n_c)
        print("  + Synthetic NDVI generation complete")
        return 0

    if hdf_path and hdf_path.exists():
        print(f"\n  Attempting real data extraction...")
        if extract_from_hdf(hdf_path, output_bin, output_hdr):
            print("  + Real NDVI extraction complete")
            return 0
        print("  - Extraction failed, falling back to synthetic")
    else:
        print(f"\n  - HDF file not found, generating synthetic data")

    sizes = {"small": (46, 100, 100), "large": (46, 500, 500), "xlarge": (46, 1200, 1200)}
    n_b, n_r, n_c = sizes[args.size]
    generate_synthetic(output_bin, output_hdr, n_b, n_r, n_c)
    print("  + Synthetic NDVI generation complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
