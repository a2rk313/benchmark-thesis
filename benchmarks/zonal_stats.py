#!/usr/bin/env python3
"""
SCENARIO F: Zonal Statistics - Python Implementation
Tests: Polygon-based raster statistics (mean, std, sum over zones)

Uses REAL NLCD land cover data when available.
Academic rationale:
- Zonal statistics is fundamental to GIS analysis
- Used in land cover analysis, climate studies, hydrology
- Tests raster-vector overlay performance
"""
from pathlib import Path

import argparse
import os
import sys
import time
import json

import numpy as np
import geopandas as gpd
import tracemalloc

sys.path.insert(0, str(Path(__file__).parent))
from core_stats import (

    generate_hash,
    shapiro_wilk_test,
    bootstrap_ci,
    run_benchmark,
)

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"


OUTPUT_DIR = Path("validation")
RESULTS_DIR = Path("results")


def load_or_create_data(data_mode="auto"):
    """Load or create test data for zonal statistics.

    Uses IDENTICAL synthetic data as Julia/R: 600x600 uniform random [0, 3000).
    This ensures fair cross-language comparison.
    """
    data_source = "synthetic"

    # Try real NLCD + polygons
    if data_mode in ("auto", "real"):
        try:
            # Try real polygons first
            poly_path = str(DATA_DIR / "natural_earth_countries.gpkg")
            if os.path.exists(poly_path):
                polys = gpd.read_file(poly_path)
                raster, rows, cols = load_nlcd_data()
                if raster is not None:
                    lats = np.linspace(90, -90, rows)
                    lons = np.linspace(-180, 180, cols)
                    print(f"  ✓ Using real data: {len(polys)} polygons + NLCD {rows}×{cols}")
                    return polys, raster, lats, lons, "real"
                elif data_mode == "real":
                    print("  x Real NLCD data required but unavailable")
                    sys.exit(1)

            if data_mode == "real":
                print("  x Real polygon data required but unavailable")
                sys.exit(1)
        except Exception as e:
            print(f"  ⚠ Real data load failed: {e}")
            if data_mode == "real":
                sys.exit(1)

    # Synthetic fallback: identical to Julia/R
    print("  → Using synthetic data (uniform random, 600x600)")
    np.random.seed(42)
    rows, cols = 600, 600
    raster = (np.random.rand(rows, cols) * 3000).astype(np.float32)
    lats = np.linspace(90, -90, rows)
    lons = np.linspace(-180, 180, cols)

    # Create synthetic polygons
    polys = create_polygon_zones(10)

    return polys, raster, lats, lons, data_source

def load_nlcd_data():
    """Load real NLCD land cover data if available."""
    nlcd_paths = [
        str(DATA_DIR / "nlcd/nlcd_landcover.bin"),
        str(DATA_DIR / "nlcd/nlcd_landcover.tif"),
    ]

    for path in nlcd_paths:
        if Path(path).exists():
            try:
                if path.endswith(".bin"):
                    hdr_path = path.replace(".bin", ".hdr")
                    if Path(hdr_path).exists():
                        with open(hdr_path) as f:
                            for line in f:
                                if line.startswith("samples"):
                                    cols = int(line.split("=")[1].strip())
                                elif line.startswith("lines"):
                                    rows = int(line.split("=")[1].strip())

                        data = np.fromfile(path, dtype=np.uint8).astype(np.float32)
                        data = data.reshape(rows, cols)
                        print(f"  ✓ Loaded NLCD land cover: {path} ({data.shape})")
                        return data, rows, cols
                elif path.endswith(".tif"):
                    import rasterio

                    with rasterio.open(path) as src:
                        data = src.read(1).astype(np.float32)
                        rows, cols = data.shape
                        print(f"  ✓ Loaded NLCD land cover: {path} ({data.shape})")
                        return data, rows, cols
            except Exception as e:
                print(f"  ⚠ Could not load {path}: {e}")

    print("  ⚠ NLCD not available, using uniform synthetic data")
    return None, 0, 0


def create_polygon_zones(n_zones: int = 10):
    """Create simple rectangular polygon zones for consistent cross-language comparison.

    All languages use identical axis-aligned rectangles spanning lat/lon ranges.
    This ensures the benchmark measures zonal statistics performance, not
    polygon complexity or library differences.
    """
    from shapely.geometry import box

    zones = []
    lat_step = 180.0 / n_zones
    lon_step = 360.0 / n_zones

    for i in range(n_zones):
        for j in range(n_zones):
            min_lon = -180.0 + j * lon_step
            max_lon = min_lon + lon_step
            min_lat = -90.0 + i * lat_step
            max_lat = min_lat + lat_step
            zones.append(box(min_lon, min_lat, max_lon, max_lat))

    import geopandas as gpd
    gdf = gpd.GeoDataFrame(geometry=zones, crs="EPSG:4326")
    return gdf


def rasterize_polygons_to_mask(gdf, rows, cols):
    """Rasterize polygons to a grid mask matching the raster extent."""
    from shapely.geometry import box

    mask = np.zeros((rows, cols), dtype=np.int32)
    lats = np.linspace(90, -90, rows)
    lons = np.linspace(-180, 180, cols)

    lat_step = 180.0 / rows
    lon_step = 360.0 / cols

    unique_zones = list(range(1, len(gdf) + 1))
    for zone_id, geom in zip(unique_zones, gdf.geometry):
        min_lon, min_lat, max_lon, max_lat = geom.bounds

        r0 = int(max(0, (90 - max_lat) / lat_step))
        r1 = int(min(rows, (90 - min_lat) / lat_step + 1))
        c0 = int(max(0, (min_lon + 180) / lon_step))
        c1 = int(min(cols, (max_lon + 180) / lon_step + 1))

        for r in range(r0, min(r1, rows)):
            for c in range(c0, min(c1, cols)):
                lat = lats[r]
                lon = lons[c]
                pt = box(lon - lon_step / 2, lat - lat_step / 2, lon + lon_step / 2, lat + lat_step / 2)
                if geom.contains(pt) or geom.intersects(pt):
                    mask[r, c] = zone_id

    return mask


def zonal_statistics_with_polygons(raster, mask, zone_ids):
    """Calculate statistics for all zones using rasterized mask."""
    results = []
    for zone_id in zone_ids:
        zone_mask = mask == zone_id
        if zone_mask.sum() == 0:
            results.append({"zone": zone_id, "mean": 0, "std": 0, "sum": 0, "count": 0})
            continue

        values = raster[zone_mask]
        results.append(
            {
                "zone": zone_id,
                "mean": float(values.mean()),
                "std": float(values.std()),
                "sum": float(values.sum()),
                "count": int(len(values)),
            }
        )
    return results


def run_zonal_stats_benchmark(data_mode="auto"):
    print("=" * 70)
    print("PYTHON - Scenario F: Zonal Statistics")
    print("=" * 70)

    print("\n[1/4] Loading data...")
    polys, raster, lats, lons, data_source = load_or_create_data(data_mode)
    rows, cols = raster.shape
    print(f"  ✓ Loaded {len(polys)} polygons")
    print(f"  ✓ Raster shape: {raster.shape} ({raster.size:,} cells)")

    results = {}
    all_hashes = []

    # Create polygon-based mask grid (consistent across all languages)
    print("\n[2/4] Creating polygon zone mask grid...")
    n_zones = 10
    gdf_zones = create_polygon_zones(n_zones)
    print(f"  ✓ Created {len(gdf_zones)} rectangular polygon zones")

    def mask_task():
        return rasterize_polygons_to_mask(gdf_zones, rows, cols)

    tracemalloc.start()
    times, peak, _ = run_benchmark(mask_task, runs=5, warmup=2)
    mask = mask_task()
    tracemalloc.stop()

    mask_hash = generate_hash(mask)
    all_hashes.append(mask_hash)

    print(f"  ✓ Mask created: {np.unique(mask).max()} zones")
    print(f"  ✓ Min: {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")

    current, peak = tracemalloc.get_traced_memory()
    results["mask_creation"] = {
        "min_time_s": min(times),
        "mean_time_s": np.mean(times),
        "std_time_s": np.std(times, ddof=1),
        "median_time_s": float(np.median(times)),
        "max_time_s": max(times),
        "times": times,
        "peak_memory_mb": peak / 1024 / 1024,
        "n_zones": n_zones * n_zones,
        "validation_hash": mask_hash,
    }

    # Full zonal statistics using polygon-based mask
    print("\n[3/4] Testing zonal statistics with polygon mask...")

    unique_zones = np.unique(mask)
    unique_zones = unique_zones[unique_zones > 0]

    def zonal_task():
        return zonal_statistics_with_polygons(raster, mask, unique_zones)

    stats_result = zonal_task()

    times, peak, _ = run_benchmark(zonal_task, runs=10, warmup=2)
    stats_hash = generate_hash(np.array([r["mean"] for r in stats_result]))
    all_hashes.append(stats_hash)

    p_val, is_norm = shapiro_wilk_test(np.array(times))
    ci_lower, ci_upper = bootstrap_ci(np.array(times))

    print(f"  ✓ Min: {min(times):.4f}s (primary)")
    print(f"  ✓ Mean: {np.mean(times):.4f}s ± {np.std(times, ddof=1):.4f}s")
    print(f"  ✓ 95% CI: [{ci_lower:.4f}, {ci_upper:.4f}]")
    print(f"  ✓ Normality: p={p_val:.4f} ({'normal' if is_norm else 'non-normal'})")
    print(f"  ✓ Hash: {stats_hash}")

    results["zonal_stats"] = {
        "min_time_s": min(times),
        "mean_time_s": np.mean(times),
        "std_time_s": np.std(times, ddof=1),
        "median_time_s": float(np.median(times)),
        "max_time_s": max(times),
        "times": times,
        "normality_p": p_val,
        "is_normal": is_norm,
        "ci_95": [ci_lower, ci_upper],
        "n_zones": len(stats_result),
        "validation_hash": stats_hash,
    }

    # Save results
    print("\n" + "=" * 70)
    print("SAVING RESULTS...")
    print("=" * 70)

    OUTPUT_DIR.mkdir(exist_ok=True)
    RESULTS_DIR.mkdir(exist_ok=True)

    output_data = {
        "language": "python",
        "scenario": "zonal_statistics",
        "data_source": data_source,
        "data_description": "Natural Earth + NLCD" if data_source == "real" else "synthetic 600x600 + 100 rectangular zones",
        "zone_type": "rectangular_polygons",
        "n_zones": n_zones * n_zones,
        "results": results,
        "all_hashes": all_hashes,
        "combined_hash": generate_hash(all_hashes),
    }

    with open(OUTPUT_DIR / "zonal_stats_python_results.json", "w") as f:
        json.dump(output_data, f, indent=2, default=str)

    with open(RESULTS_DIR / "zonal_stats_python.json", "w") as f:
        json.dump(output_data, f, indent=2, default=str)

    print(f"✓ Results saved")
    print(f"✓ Combined validation hash: {output_data['combined_hash']}")

    print("\n" + "=" * 70)
    print("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    print("=" * 70)

    return output_data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Zonal Statistics Benchmark")
    parser.add_argument("--data", choices=["auto", "real", "synthetic"],
                       default="auto", help="Data source: auto=real→synthetic, real, synthetic")
    args = parser.parse_args()
    run_zonal_stats_benchmark(data_mode=args.data)