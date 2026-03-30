#!/usr/bin/env python3
"""
================================================================================
Standardized Test Data Generator for GIS/Remote Sensing Benchmarks
================================================================================

Generates consistent test datasets for benchmarking across Python, Julia, and R.
Ensures reproducibility and fairness in cross-language comparisons.

Usage:
    python tools/generate_benchmark_data.py --all          # Generate all datasets
    python tools/generate_benchmark_data.py --hsi          # Hyperspectral data
    python tools/generate_benchmark_data.py --gps          # GPS points
    python tools/generate_benchmark_data.py --vector       # Vector polygons
    python tools/generate_benchmark_data.py --io           # I/O test files
================================================================================
"""

import argparse
import numpy as np
import pandas as pd
from pathlib import Path
import json
from datetime import datetime


def generate_hsi_data(
    output_path="data/cuprite_synthetic.mat", n_bands=224, n_rows=512, n_cols=614
):
    """
    Generate synthetic hyperspectral data similar to AVIRIS Cuprite.

    Creates a realistic HSI cube with:
    - Noise characteristics similar to real AVIRIS data
    - Spectral signatures resembling common minerals
    - Spatial structure (not pure random noise)
    """
    print(f"\n[1/4] Generating Hyperspectral Data...")
    print(f"  Shape: {n_bands} bands × {n_rows}×{n_cols} pixels")

    # Generate base signal (spatial structure)
    x = np.linspace(0, 4 * np.pi, n_cols)
    y = np.linspace(0, 4 * np.pi, n_rows)
    xx, yy = np.meshgrid(x, y)

    # Create spatial patterns (mineral-like signatures)
    signal = (
        0.3 * np.sin(xx + yy) + 0.2 * np.sin(2 * xx - yy) + 0.1 * np.cos(xx * yy / 10)
    )

    # Add spectral variation
    spectral_pattern = np.linspace(0.8, 1.2, n_bands)

    # Build the HSI cube
    data = np.zeros((n_bands, n_rows, n_cols), dtype=np.int16)
    for b in range(n_bands):
        # Add noise and spectral scaling
        noise = np.random.randn(n_rows, n_cols) * 100
        data[b, :, :] = ((signal + noise) * spectral_pattern[b] * 100 + 1000).astype(
            np.int16
        )

    # Save as MATLAB file
    try:
        import scipy.io as sio

        sio.savemat(output_path, {"X": data})
        size = Path(output_path).stat().st_size / 1024 / 1024
        print(f"  ✓ Saved: {output_path} ({size:.1f} MB)")
        return True
    except Exception as e:
        print(f"  ⚠ Could not save .mat file: {e}")
        # Save as numpy for fallback
        np_path = output_path.replace(".mat", ".npy")
        np.save(np_path, data.astype(np.float32))
        print(f"  ✓ Saved (numpy fallback): {np_path}")
        return True


def generate_gps_points(output_path="data/gps_points_1m.csv", n_points=1_000_000):
    """
    Generate synthetic GPS tracking data.

    Creates realistic GPS points with:
    - Global distribution
    - Temporal clustering
    - Multiple device IDs
    - Realistic accuracy values
    """
    print(f"\n[2/4] Generating GPS Points...")
    print(f"  Points: {n_points:,}")

    np.random.seed(42)  # Reproducible

    # Generate timestamp range (1 year of data)
    start_date = datetime(2024, 1, 1)
    timestamps = [
        start_date.timestamp() + np.random.uniform(0, 365 * 24 * 3600)
        for _ in range(n_points)
    ]

    # Create device IDs (clustered around certain devices)
    n_devices = max(10, n_points // 100000)  # ~10 devices per 1M points
    device_ids = np.random.choice(range(1, n_devices + 1), size=n_points)

    # Generate positions with some clustering
    # (Real GPS data has spatial clustering)
    lat = np.random.uniform(-90, 90, n_points)
    lon = np.random.uniform(-180, 180, n_points)

    # Add some clusters (cities/POIs)
    n_clusters = 50
    for _ in range(n_clusters):
        center_lat = np.random.uniform(-90, 90)
        center_lon = np.random.uniform(-180, 180)
        n_cluster_points = n_points // 500  # Small cluster
        indices = np.random.choice(n_points, n_cluster_points, replace=False)
        lat[indices] += np.random.randn(n_cluster_points) * 0.5
        lon[indices] += np.random.randn(n_cluster_points) * 0.5

    # Clip to valid ranges
    lat = np.clip(lat, -90, 90)
    lon = np.clip(lon, -180, 180)

    # Generate accuracy (realistic range: 1-50m typically)
    accuracy = np.random.exponential(5, n_points) + 1
    accuracy = np.clip(accuracy, 1, 100)

    # Create DataFrame and save
    df = pd.DataFrame(
        {
            "lat": lat,
            "lon": lon,
            "device_id": device_ids,
            "timestamp": [
                datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")
                for t in timestamps
            ],
            "accuracy_m": accuracy,
        }
    )

    df.to_csv(output_path, index=False)
    size = Path(output_path).stat().st_size / 1024 / 1024
    print(f"  ✓ Saved: {output_path} ({size:.1f} MB)")
    print(f"  Columns: {', '.join(df.columns)}")

    return True


def generate_io_test_data(output_dir="data", n_rows=1_000_000):
    """
    Generate I/O test files in various formats.
    """
    print(f"\n[3/4] Generating I/O Test Files...")

    # Generate test data
    np.random.seed(42)
    lat = np.random.uniform(-90, 90, n_rows)
    lon = np.random.uniform(-180, 180, n_rows)
    value = np.random.randn(n_rows)

    # CSV file
    csv_path = f"{output_dir}/io_test.csv"
    df = pd.DataFrame({"lat": lat, "lon": lon, "value": value})
    df.to_csv(csv_path, index=False)
    size = Path(csv_path).stat().st_size / 1024 / 1024
    print(f"  ✓ CSV: {csv_path} ({size:.1f} MB)")

    # Binary file (float64)
    bin_path = f"{output_dir}/io_test.bin"
    value.astype(np.float64).tofile(bin_path)
    size = Path(bin_path).stat().st_size / 1024 / 1024
    print(f"  ✓ Binary: {bin_path} ({size:.1f} MB)")

    # NumPy .npy file
    npy_path = f"{output_dir}/io_test.npy"
    np.save(npy_path, value.astype(np.float32))
    size = Path(npy_path).stat().st_size / 1024 / 1024
    print(f"  ✓ NumPy: {npy_path} ({size:.1f} MB)")

    return True


def generate_vector_data(
    output_path="data/countries_synthetic.geojson", n_countries=50
):
    """
    Generate synthetic polygon data (country-like boundaries).

    For real data, use Natural Earth or similar sources.
    This creates simple rectangular polygons for testing.
    """
    print(f"\n[4/4] Generating Vector Polygons...")
    print(f"  Note: For real boundaries, use Natural Earth data")

    try:
        import geopandas as gpd
        from shapely.geometry import box, Polygon

        np.random.seed(42)
        geometries = []
        names = []

        # Create grid of country-like boxes
        lat_step = 180 / (n_countries // 2 + 1)
        lon_step = 360 / (n_countries // 2 + 1)

        idx = 0
        for i in range(n_countries // 2 + 1):
            for j in range(n_countries // 2 + 1):
                if idx >= n_countries:
                    break

                # Random box with some variation
                min_lon = -180 + j * lon_step + np.random.uniform(-2, 2)
                max_lon = min_lon + lon_step + np.random.uniform(-2, 2)
                min_lat = -90 + i * lat_step + np.random.uniform(-2, 2)
                max_lat = min_lat + lat_step + np.random.uniform(-2, 2)

                # Clip to valid ranges
                min_lon, max_lon = max(-180, min_lon), min(180, max_lon)
                min_lat, max_lat = max(-90, min_lat), min(90, max_lat)

                if max_lon > min_lon and max_lat > min_lat:
                    geom = box(min_lon, min_lat, max_lon, max_lat)
                    geometries.append(geom)
                    names.append(f"Country_{idx + 1}")
                    idx += 1

                if idx >= n_countries:
                    break

        gdf = gpd.GeoDataFrame(
            {
                "name": names,
                "area_km2": [g.area * 111**2 for g in geometries],  # Rough km²
            },
            geometry=geometries,
            crs="EPSG:4326",
        )

        gdf.to_file(output_path, driver="GeoJSON")
        size = Path(output_path).stat().st_size / 1024 / 1024
        print(f"  ✓ Saved: {output_path} ({size:.1f} MB)")
        print(f"  Features: {len(gdf)}")

        return True

    except ImportError:
        print(f"  ⚠ geopandas not available, skipping vector data")
        return False
    except Exception as e:
        print(f"  ⚠ Error generating vector data: {e}")
        return False


def create_dataset_metadata(data_dir="data"):
    """
    Create metadata file documenting all datasets.
    """
    metadata = {
        "created": datetime.now().isoformat(),
        "datasets": {
            "cuprite_synthetic.mat": {
                "description": "Synthetic hyperspectral imagery (AVIRIS-like)",
                "shape": "224 bands × 512 × 614 pixels",
                "dtype": "int16",
                "use": "HSI processing, band math, spectral indices",
            },
            "gps_points_1m.csv": {
                "description": "Synthetic GPS tracking points",
                "records": 1_000_000,
                "columns": ["lat", "lon", "device_id", "timestamp", "accuracy_m"],
                "use": "Spatial interpolation, point operations",
            },
            "countries_synthetic.geojson": {
                "description": "Synthetic country polygons",
                "features": 50,
                "use": "Point-in-polygon, zonal statistics",
            },
        },
    }

    meta_path = Path(data_dir) / "datasets_metadata.json"
    with open(meta_path, "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"\n  ✓ Metadata: {meta_path}")
    return metadata


def main():
    parser = argparse.ArgumentParser(description="Generate benchmark test data")
    parser.add_argument("--all", action="store_true", help="Generate all datasets")
    parser.add_argument("--hsi", action="store_true", help="Generate HSI data")
    parser.add_argument("--gps", action="store_true", help="Generate GPS points")
    parser.add_argument("--io", action="store_true", help="Generate I/O test files")
    parser.add_argument(
        "--vector", action="store_true", help="Generate vector polygons"
    )
    parser.add_argument("--data-dir", default="data", help="Output directory")

    args = parser.parse_args()

    print("=" * 70)
    print("BENCHMARK TEST DATA GENERATOR")
    print("=" * 70)

    # Create data directory
    data_dir = Path(args.data_dir)
    data_dir.mkdir(exist_ok=True)

    # Default: generate all if no specific option
    generate_all = args.all or not any([args.hsi, args.gps, args.io, args.vector])

    if generate_all or args.hsi:
        generate_hsi_data(str(data_dir / "cuprite_synthetic.mat"))

    if generate_all or args.gps:
        generate_gps_points(str(data_dir / "gps_points_1m.csv"))

    if generate_all or args.io:
        generate_io_test_data(str(data_dir))

    if generate_all or args.vector:
        generate_vector_data(str(data_dir / "countries_synthetic.geojson"))

    if generate_all:
        create_dataset_metadata(str(data_dir))

    print("\n" + "=" * 70)
    print("✓ DATA GENERATION COMPLETE")
    print("=" * 70)
    print(f"\nLocation: {data_dir}")
    print("\nNext steps:")
    print("  1. Review datasets: ls -lh data/")
    print("  2. Run benchmarks: mise run bench")
    print()


if __name__ == "__main__":
    main()
