#!/usr/bin/env python3
"""
===============================================================================
Data Download: Cuprite Hyperspectral Dataset (MAT format)
===============================================================================
Downloads the Cuprite AVIRIS dataset for raster benchmarking.
Dataset: Cuprite, Nevada – 224 bands, ~95 MB
Source: Hyperspectral Remote Sensing Scenes (GIC, University of the Basque Country)
===============================================================================
"""

import os
import urllib.request
from pathlib import Path
import hashlib

def download_with_progress(url, output_path):
    """Download file with a simple progress bar."""
    def report_progress(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            percent = min(100, downloaded * 100 / total_size)
            mb_downloaded = downloaded / (1024**2)
            mb_total = total_size / (1024**2)
            print(f"\r  Progress: {percent:.1f}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)", end='')
    urllib.request.urlretrieve(url, output_path, reporthook=report_progress)
    print()  # new line after progress

def verify_checksum(file_path, expected_md5=None):
    """Calculate and optionally verify MD5 checksum."""
    print("  Calculating checksum...")
    md5_hash = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            md5_hash.update(chunk)
    actual_md5 = md5_hash.hexdigest()
    print(f"  ✓ MD5: {actual_md5}")
    if expected_md5 and actual_md5 != expected_md5:
        print(f"  ⚠ WARNING: Checksum mismatch!")
        print(f"    Expected: {expected_md5}")
        print(f"    Got: {actual_md5}")
        return False
    return True

def download_cuprite():
    """
    Download Cuprite dataset (AVIRIS, 224 bands) from the official GIC repository.
    """
    print("\n[1/2] Downloading Cuprite Hyperspectral Dataset...")

    # Primary download source (verified working as of March 2025)
    download_sources = [
        {
            "name": "GIC Repository (Cuprite)",
            "url": "https://www.ehu.eus/ccwintco/uploads/7/7d/Cuprite_f970619t01p02_r02_sc03.a.rfl.mat",
            "md5": None,  # No public MD5, but we'll compute it
            "filename": "Cuprite.mat"
        }
    ]

    data_dir = Path("data")
    data_dir.mkdir(exist_ok=True)
    output_path = data_dir / "Cuprite.mat"

    downloaded = False
    for source in download_sources:
        if downloaded:
            break
        try:
            print(f"\n  Downloading from: {source['name']}")
            print(f"  URL: {source['url']}")

            if not output_path.exists():
                download_with_progress(source['url'], output_path)
                print("  ✓ Download complete")
            else:
                print("  ✓ Using cached file (already exists)")

            # File size sanity check
            file_size_mb = output_path.stat().st_size / (1024**2)
            print(f"  ✓ File size: {file_size_mb:.2f} MB")
            if file_size_mb < 1:
                print("  ⚠ File is too small – likely corrupted")
                output_path.unlink()
                continue

            # Optional checksum verification (just display; no expected value)
            verify_checksum(output_path)

            downloaded = True

        except Exception as e:
            print(f"  ✗ Download failed: {e}")
            if output_path.exists():
                output_path.unlink()
            continue

    if not downloaded:
        print("\n  ✗ All download attempts failed.")
        print("\n  Manual download instructions:")
        print("  1. Visit: https://www.ehu.eus/ccwintco/index.php/Hyperspectral_Remote_Sensing_Scenes")
        print("  2. Look for the 'Cuprite' dataset (AVIRIS, 224 bands).")
        print("  3. Download the MATLAB file (Cuprite_f970619t01p02_r02_sc03.a.rfl.mat).")
        print("  4. Place it in the 'data/' directory and rename it to 'Cuprite.mat'.")
        print("  5. Re-run this script to verify.")
        return False

    # Summary
    print("\n" + "=" * 70)
    print("HYPERSPECTRAL DATA DOWNLOAD COMPLETE")
    print("=" * 70)
    print(f"\nDataset: AVIRIS Cuprite (224 bands)")
    print(f"Location: {output_path}")
    print(f"Size: {file_size_mb:.2f} MB")
    print("\nYou can now run the raster benchmarks.")
    print("=" * 70)

    return True

def main():
    print("=" * 70)
    print("HYPERSPECTRAL DATA DOWNLOAD: AVIRIS Cuprite")
    print("=" * 70)

    success = download_cuprite()

    if not success:
        print("\n⚠ Data preparation incomplete. Please download manually.")
        return 1

    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
