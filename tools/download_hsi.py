#!/usr/bin/env python3
"""
===============================================================================
Data Download: NASA AVIRIS Hyperspectral Imagery
===============================================================================
Downloads the Jasper Ridge hyperspectral dataset for raster benchmarking.
Dataset: AVIRIS Jasper Ridge (224 bands, ~100MB compressed)
Source: Hyperspectral Remote Sensing Scenes - Grupo de Inteligencia Computacional (GIC)
===============================================================================
"""

import os
import urllib.request
import zipfile
from pathlib import Path
import hashlib

def download_with_progress(url, output_path):
    """Download file with progress bar"""
    
    def report_progress(block_num, block_size, total_size):
        downloaded = block_num * block_size
        percent = min(100, (downloaded / total_size) * 100)
        mb_downloaded = downloaded / (1024**2)
        mb_total = total_size / (1024**2)
        print(f"\r  Progress: {percent:.1f}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)", end='')
    
    urllib.request.urlretrieve(url, output_path, reporthook=report_progress)
    print()  # New line after progress

def verify_checksum(file_path, expected_md5=None):
    """Verify file integrity using MD5 checksum"""
    print(f"  Calculating checksum...")
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

def download_jasper_ridge():
    """
    Download AVIRIS Jasper Ridge hyperspectral dataset
    
    Dataset details:
    - Scene: Jasper Ridge, California
    - Sensor: AVIRIS (Airborne Visible/Infrared Imaging Spectrometer)
    - Bands: 224 (calibrated and atmospherically corrected)
    - Wavelength range: 380-2500 nm
    - Format: BSQ (Band Sequential)
    - Size: ~100 MB compressed, ~600 MB uncompressed
    """
    print("\n[1/3] Downloading AVIRIS Jasper Ridge Dataset...")
    
    # Alternative download sources (in case primary fails)
    download_sources = [
        {
            "name": "GIC Repository (Primary)",
            "url": "http://www.ehu.eus/ccwintco/uploads/2/22/Jasper.zip",
            "md5": None  # Add if known
        },
        {
            "name": "Mirror (Backup)",
            "url": "https://github.com/YerevaNN/r-fcn-3d-object-detection/raw/master/data/Jasper.zip",
            "md5": None
        }
    ]
    
    # Create data directory
    data_dir = Path("data")
    data_dir.mkdir(exist_ok=True)
    
    zip_path = data_dir / "jasper_ridge.zip"
    extract_dir = data_dir / "jasperRidge2_R198"
    
    # Try download sources in order
    downloaded = False
    for source in download_sources:
        if downloaded:
            break
            
        try:
            print(f"\n  Trying source: {source['name']}")
            print(f"  URL: {source['url']}")
            
            if not zip_path.exists():
                download_with_progress(source['url'], zip_path)
                print(f"  ✓ Downloaded successfully")
            else:
                print(f"  ✓ Using cached download")
            
            # Verify file size (sanity check)
            file_size_mb = zip_path.stat().st_size / (1024**2)
            print(f"  ✓ File size: {file_size_mb:.2f} MB")
            
            if file_size_mb < 1:
                print(f"  ⚠ File too small, likely corrupted")
                zip_path.unlink()
                continue
            
            # Verify checksum if available
            if source.get('md5'):
                if not verify_checksum(zip_path, source['md5']):
                    zip_path.unlink()
                    continue
            else:
                verify_checksum(zip_path)
            
            downloaded = True
            
        except Exception as e:
            print(f"  ✗ Failed: {e}")
            if zip_path.exists():
                zip_path.unlink()
            continue
    
    if not downloaded:
        print("\n  ✗ All download sources failed!")
        print("\n  Manual download instructions:")
        print("  1. Visit: http://www.ehu.eus/ccwintco/index.php/Hyperspectral_Remote_Sensing_Scenes")
        print("  2. Download 'Jasper Ridge' dataset")
        print("  3. Place 'Jasper.zip' in the 'data/' directory")
        print("  4. Re-run this script")
        return False
    
    # Extract
    print("\n[2/3] Extracting dataset...")
    
    if extract_dir.exists():
        print(f"  ✓ Dataset already extracted to {extract_dir}")
    else:
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(data_dir)
            print(f"  ✓ Extracted to {data_dir}")
        except Exception as e:
            print(f"  ✗ Extraction failed: {e}")
            return False
    
    # Verify extracted files
    print("\n[3/3] Verifying extracted data...")
    
    # Look for the main data file (filename varies)
    possible_names = [
        "jasperRidge2_R198",
        "jasperRidge2",
        "Jasper"
    ]
    
    found_file = None
    for name in possible_names:
        test_path = data_dir / name / name
        if test_path.exists():
            found_file = test_path
            break
        # Also check without subdirectory
        test_path = data_dir / name
        if test_path.exists():
            found_file = test_path
            break
    
    if found_file:
        file_size_gb = found_file.stat().st_size / (1024**3)
        print(f"  ✓ Found data file: {found_file}")
        print(f"  ✓ Size: {file_size_gb:.2f} GB")
        
        # Check for header file
        header_file = found_file.with_suffix('.hdr')
        if header_file.exists():
            print(f"  ✓ Found header file: {header_file}")
        else:
            print(f"  ⚠ Header file not found (expected at {header_file})")
        
        # Create consistent symlink for benchmarks
        expected_dir = data_dir / "jasperRidge2_R198"
        expected_file = expected_dir / "jasperRidge2_R198"
        
        if not expected_file.exists():
            print(f"\n  Creating consistent path for benchmarks...")
            expected_dir.mkdir(parents=True, exist_ok=True)
            
            # Create symlink to actual file
            try:
                if found_file != expected_file:
                    import shutil
                    shutil.copy2(found_file, expected_file)
                    if header_file.exists():
                        expected_header = expected_file.with_suffix('.hdr')
                        shutil.copy2(header_file, expected_header)
                    print(f"  ✓ Created consistent path: {expected_file}")
            except Exception as e:
                print(f"  ⚠ Could not create symlink: {e}")
                print(f"  You may need to manually copy the file to: {expected_file}")
    else:
        print(f"  ✗ Could not locate data file in {data_dir}")
        print(f"  Searched for: {', '.join(possible_names)}")
        return False
    
    # Summary
    print("\n" + "=" * 70)
    print("HYPERSPECTRAL DATA DOWNLOAD COMPLETE")
    print("=" * 70)
    print(f"\nDataset: AVIRIS Jasper Ridge")
    print(f"Location: {found_file}")
    print(f"Size: {file_size_gb:.2f} GB")
    print(f"\nYou can now run the raster benchmarks.")
    print("=" * 70)
    
    return True

def main():
    print("=" * 70)
    print("HYPERSPECTRAL DATA DOWNLOAD: NASA AVIRIS Jasper Ridge")
    print("=" * 70)
    
    success = download_jasper_ridge()
    
    if not success:
        print("\n⚠ Data preparation incomplete. Please download manually.")
        return 1
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
