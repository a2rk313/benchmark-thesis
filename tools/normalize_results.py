#!/usr/bin/env python3
"""
Normalize benchmark results from different sources into a unified format.

This resolves the issue of mixed container vs native result formats and
ensures consistent data structures for visualization and analysis.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Any
import argparse

def normalize_single_result(result_path: Path) -> Dict[str, Any]:
    """
    Normalize a single result file to unified format.
    
    Args:
        result_path: Path to result JSON file
        
    Returns:
        Normalized result dictionary
    """
    try:
        with open(result_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Warning: Could not read {result_path}: {e}", file=sys.stderr)
        return None
    
    # Unified result format
    normalized = {
        "language": "",
        "benchmark": "",
        "scenario": "",
        "min_time_s": 0.0,
        "mean_time_s": 0.0,
        "std_time_s": 0.0,
        "max_time_s": 0.0,
        "ci_95_lower": 0.0,
        "ci_95_upper": 0.0,
        "cv": 0.0,
        "runs": 0,
        "warmup": 0,
        "memory_rss_mb": None,
        "memory_vms_mb": None,
        "validation_hash": "",
        "source_file": str(result_path),
        "mode": "unknown"  # container or native
    }
    
    # Extract language from filename or data
    filename = result_path.name.lower()
    if "python" in filename:
        normalized["language"] = "Python"
    elif "julia" in filename:
        normalized["language"] = "Julia"
    elif "r" in filename and "results" not in filename:
        normalized["language"] = "R"
    
    # Try to extract benchmark name from filename
    if "matrix" in filename:
        normalized["benchmark"] = "matrix_ops"
        normalized["scenario"] = "matrix_operations"
    elif "io" in filename:
        normalized["benchmark"] = "io_ops"
        normalized["scenario"] = "io_operations"
    elif "vector" in filename:
        normalized["benchmark"] = "vector_pip"
        normalized["scenario"] = "vector_point_in_polygon"
    elif "hsi" in filename or "hyperspectral" in filename:
        normalized["benchmark"] = "hsi_stream"
        normalized["scenario"] = "hyperspectral_sam"
    elif "interpolation" in filename or "idw" in filename:
        normalized["benchmark"] = "interpolation_idw"
        normalized["scenario"] = "spatial_interpolation"
    elif "timeseries" in filename or "ndvi" in filename:
        normalized["benchmark"] = "timeseries_ndvi"
        normalized["scenario"] = "time_series_ndvi"
    elif "reprojection" in filename:
        normalized["benchmark"] = "reprojection"
        normalized["scenario"] = "coordinate_reprojection"
    elif "zonal" in filename:
        normalized["benchmark"] = "zonal_stats"
        normalized["scenario"] = "zonal_statistics"
    elif "raster" in filename:
        normalized["benchmark"] = "raster_algebra"
        normalized["scenario"] = "raster_algebra"
    
    # Try to extract timing data from various formats
    if isinstance(data, dict):
        # Handle different data structures
        if "results" in data and isinstance(data["results"], dict):
            # Standard format with results dict
            results = data["results"]
            for key in results:
                if isinstance(results[key], dict) and "min" in results[key]:
                    # Take the first benchmark with min time
                    bench_data = results[key]
                    normalized["min_time_s"] = bench_data.get("min", 0.0)
                    normalized["mean_time_s"] = bench_data.get("mean", 0.0)
                    normalized["std_time_s"] = bench_data.get("std", 0.0)
                    normalized["max_time_s"] = bench_data.get("max", 0.0)
                    break
        elif "min_time_s" in data:
            # Already normalized format
            normalized.update({k: v for k, v in data.items() if k in normalized})
        elif "min" in data:
            # Simple format
            normalized["min_time_s"] = data.get("min", 0.0)
            normalized["mean_time_s"] = data.get("mean", data.get("min", 0.0))
            normalized["std_time_s"] = data.get("std", 0.0)
            normalized["max_time_s"] = data.get("max", data.get("min", 0.0))
        
        # Extract other metadata
        if "language" in data:
            lang_val = data["language"]
            if isinstance(lang_val, str):
                normalized["language"] = lang_val.capitalize()
            elif isinstance(lang_val, list) and len(lang_val) > 0:
                normalized["language"] = str(lang_val[0]).capitalize()
        if "validation_hash" in data:
            normalized["validation_hash"] = data["validation_hash"]
        if "n_runs" in data:
            normalized["runs"] = data["n_runs"]
        if "n_warmup" in data:
            normalized["warmup"] = data["n_warmup"]
        if "memory_rss_mb" in data:
            normalized["memory_rss_mb"] = data["memory_rss_mb"]
        if "memory_vms_mb" in data:
            normalized["memory_vms_mb"] = data["memory_vms_mb"]
    
    return normalized

def scan_and_normalize_results(input_dir: Path) -> List[Dict[str, Any]]:
    """
    Scan directory for result files and normalize them.
    
    Args:
        input_dir: Directory to scan for results
        
    Returns:
        List of normalized results
    """
    normalized_results = []
    
    # Look for result files in various locations
    patterns = [
        "results/*.json",
        "results/native/*.json",
        "results/container/*.json",
        "results/warm_start/*.json",
        "results/cold_start/*.json",
        "validation/*results.json",
        "*_results.json"
    ]
    
    found_files = set()
    for pattern in patterns:
        for file_path in input_dir.glob(pattern):
            if file_path.is_file() and file_path not in found_files:
                found_files.add(file_path)
                normalized = normalize_single_result(file_path)
                if normalized:
                    # Determine mode from path
                    path_str = str(file_path)
                    if "container" in path_str or "docker" in path_str or "podman" in path_str:
                        normalized["mode"] = "container"
                    elif "native" in path_str:
                        normalized["mode"] = "native"
                    else:
                        normalized["mode"] = "unknown"
                    
                    normalized_results.append(normalized)
    
    return normalized_results

def generate_summary(normalized_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Generate summary statistics from normalized results.
    
    Args:
        normalized_results: List of normalized results
        
    Returns:
        Summary dictionary
    """
    summary = {
        "total_benchmarks": len(normalized_results),
        "languages": {},
        "benchmarks": {},
        "modes": {}
    }
    
    for result in normalized_results:
        lang = result["language"]
        bench = result["benchmark"]
        mode = result["mode"]
        
        # Count languages
        if lang not in summary["languages"]:
            summary["languages"][lang] = 0
        summary["languages"][lang] += 1
        
        # Count benchmarks
        if bench not in summary["benchmarks"]:
            summary["benchmarks"][bench] = 0
        summary["benchmarks"][bench] += 1
        
        # Count modes
        if mode not in summary["modes"]:
            summary["modes"][mode] = 0
        summary["modes"][mode] += 1
    
    return summary

def main():
    parser = argparse.ArgumentParser(description="Normalize benchmark results")
    parser.add_argument("--input", "-i", type=Path, default=Path("."), 
                       help="Input directory to scan for results")
    parser.add_argument("--output", "-o", type=Path, default=Path("results/normalized"), 
                       help="Output directory for normalized results")
    parser.add_argument("--summary", "-s", action="store_true",
                       help="Generate summary statistics")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("NORMALIZING BENCHMARK RESULTS")
    print("=" * 60)
    print(f"Input directory: {args.input}")
    print(f"Output directory: {args.output}")
    print()
    
    # Create output directory
    args.output.mkdir(parents=True, exist_ok=True)
    
    # Scan and normalize results
    normalized_results = scan_and_normalize_results(args.input)
    
    if not normalized_results:
        print("No result files found!")
        return 1
    
    print(f"Found {len(normalized_results)} result files")
    
    # Save normalized results
    output_file = args.output / "normalized_results.json"
    with open(output_file, 'w') as f:
        json.dump(normalized_results, f, indent=2)
    print(f"Saved normalized results to {output_file}")
    
    # Generate summary if requested
    if args.summary:
        summary = generate_summary(normalized_results)
        summary_file = args.output / "summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        print(f"Saved summary to {summary_file}")
        
        # Print summary
        print("\nSUMMARY:")
        print(f"  Total benchmarks: {summary['total_benchmarks']}")
        print("  By language:")
        for lang, count in summary["languages"].items():
            print(f"    {lang}: {count}")
        print("  By benchmark:")
        for bench, count in summary["benchmarks"].items():
            print(f"    {bench}: {count}")
        print("  By mode:")
        for mode, count in summary["modes"].items():
            print(f"    {mode}: {count}")
    
    print("\n✓ Normalization complete!")
    return 0

if __name__ == "__main__":
    sys.exit(main())