#!/usr/bin/env python3
"""
================================================================================
Unified Result Normalizer for Thesis Benchmarks
================================================================================

Converts various benchmark output formats (hyperfine JSON, Python JSON, 
machine-readable logs) into a standardized format for visualization and analysis.

Usage:
    python tools/normalize_results.py --input results/ --output results/normalized/
    python tools/normalize_results.py --file results/warm_start/vector_python_warm.json
    
Output Format:
    {
        "benchmark": "vector_pip",
        "language": "python",
        "execution_mode": "warm",  # cold|warm|native
        "min_time_ms": 123.45,
        "mean_time_ms": 130.0,
        "std_time_ms": 5.2,
        "runs": 30,
        "warmup_runs": 5,
        "times_ms": [121, 123, 125, ...],
        "metadata": {
            "timestamp": "2024-01-15T10:00:00",
            "cpu_freq_mhz": 3200,
            "memory_mb": 256.5,
            "hardware_info": {...}
        }
    }

================================================================================
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False


def parse_hyperfine_json(filepath: Path) -> Optional[Dict[str, Any]]:
    """Parse hyperfine JSON output (from container benchmarks)."""
    try:
        with open(filepath) as f:
            data = json.load(f)
        
        results = data.get("results", [])
        if not results:
            return None
            
        result = results[0]  # hyperfine produces one result per command
        times = result.get("times", [])
        
        if not times:
            return None
        
        # Convert seconds to milliseconds
        times_ms = [t * 1000 for t in times]
        
        return {
            "min_time_ms": result.get("min", min(times)) * 1000,
            "mean_time_ms": result.get("mean", sum(times) / len(times)) * 1000,
            "std_time_ms": result.get("stddev", 0) * 1000,
            "median_time_ms": sorted(times_ms)[len(times_ms) // 2],
            "runs": len(times),
            "times_ms": times_ms,
            "source_format": "hyperfine",
        }
    except Exception as e:
        print(f"Error parsing hyperfine JSON {filepath}: {e}", file=sys.stderr)
        return None


def parse_benchmark_stats_json(filepath: Path) -> Optional[Dict[str, Any]]:
    """Parse native benchmark_stats.py output."""
    try:
        with open(filepath) as f:
            data = json.load(f)
        
        # Handle both single result and list of results
        if isinstance(data, list):
            data = data[0] if data else None
        
        if not data:
            return None
        
        # Extract timing data
        min_time = data.get("min_time_s", data.get("min_time", 0))
        mean_time = data.get("mean_time_s", data.get("mean_time", 0))
        std_time = data.get("std_time_s", data.get("std_time", 0))
        times = data.get("times", [])
        
        # Convert to milliseconds
        return {
            "min_time_ms": min_time * 1000,
            "mean_time_ms": mean_time * 1000,
            "std_time_ms": std_time * 1000,
            "median_time_ms": data.get("median_time_s", data.get("median_time", mean_time)) * 1000,
            "runs": data.get("runs", len(times)),
            "times_ms": [t * 1000 for t in times] if times else [],
            "memory_mb": data.get("memory_peak_mb"),
            "cpu_freq_mhz": data.get("cpu_freq_mhz"),
            "output_hash": data.get("output_hash"),
            "source_format": "benchmark_stats",
        }
    except Exception as e:
        print(f"Error parsing benchmark_stats JSON {filepath}: {e}", file=sys.stderr)
        return None


def infer_benchmark_info(filepath: Path) -> Dict[str, str]:
    """Infer benchmark name, language, and mode from file path."""
    filename = filepath.stem
    parts = filename.split("_")
    
    info = {
        "benchmark": "unknown",
        "language": "unknown",
        "execution_mode": "unknown",
    }
    
    # Pattern: {benchmark}_{language}_{mode}
    # Examples: vector_python_warm.json, hsi_julia_cold.json
    
    # Language detection
    if "python" in filename.lower():
        info["language"] = "python"
    elif "julia" in filename.lower():
        info["language"] = "julia"
    elif "r_" in filename.lower() or filename.lower().endswith("_r"):
        info["language"] = "r"
    
    # Mode detection
    if "cold" in filename.lower():
        info["execution_mode"] = "cold"
    elif "warm" in filename.lower():
        info["execution_mode"] = "warm"
    elif "native" in str(filepath).lower():
        info["execution_mode"] = "native"
    else:
        info["execution_mode"] = "container"
    
    # Benchmark type detection
    benchmark_patterns = {
        "vector": "vector_pip",
        "hsi": "hsi_stream",
        "hyperspectral": "hsi_stream",
        "matrix": "matrix_ops",
        "io": "io_ops",
        "raster": "raster_algebra",
        "zonal": "zonal_stats",
        "interp": "interpolation_idw",
        "ndvi": "timeseries_ndvi",
        "reprojection": "reprojection",
    }
    
    for pattern, benchmark in benchmark_patterns.items():
        if pattern in filename.lower():
            info["benchmark"] = benchmark
            break
    
    return info


def load_hardware_info() -> Optional[Dict[str, Any]]:
    """Load hardware info if available."""
    hw_path = Path("results/hardware_info.json")
    if hw_path.exists():
        try:
            with open(hw_path) as f:
                return json.load(f)
        except Exception:
            pass
    return None


def normalize_file(filepath: Path) -> Optional[Dict[str, Any]]:
    """Normalize a single result file."""
    if not filepath.exists():
        return None
    
    # Try different parsers
    data = None
    
    # Check file content to determine format
    try:
        with open(filepath) as f:
            content = f.read(1000)  # Read first 1KB
        
        if '"command"' in content and '"results"' in content:
            # Likely hyperfine format
            data = parse_hyperfine_json(filepath)
        elif '"min_time_s"' in content or '"min_time"' in content:
            # Likely benchmark_stats format
            data = parse_benchmark_stats_json(filepath)
        else:
            # Try both parsers
            data = parse_hyperfine_json(filepath)
            if not data:
                data = parse_benchmark_stats_json(filepath)
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        return None
    
    if not data:
        return None
    
    # Add inferred info
    info = infer_benchmark_info(filepath)
    data.update(info)
    
    # Add metadata
    metadata = {
        "timestamp": datetime.fromtimestamp(filepath.stat().st_mtime).isoformat(),
        "source_file": str(filepath),
        "normalized_at": datetime.now().isoformat(),
    }
    
    # Try to load hardware info
    hw_info = load_hardware_info()
    if hw_info:
        metadata["hardware"] = hw_info
    
    data["metadata"] = metadata
    
    return data


def normalize_directory(input_dir: Path, output_dir: Path) -> List[Path]:
    """Normalize all results in a directory."""
    output_dir.mkdir(parents=True, exist_ok=True)
    
    normalized = []
    
    # Recursively find all JSON files
    for filepath in input_dir.rglob("*.json"):
        # Skip already normalized files
        if "normalized" in str(filepath):
            continue
            
        data = normalize_file(filepath)
        if data:
            # Create normalized filename
            benchmark = data.get("benchmark", "unknown")
            language = data.get("language", "unknown")
            mode = data.get("execution_mode", "unknown")
            
            normalized_name = f"{benchmark}_{language}_{mode}.json"
            output_path = output_dir / normalized_name
            
            with open(output_path, "w") as f:
                json.dump(data, f, indent=2)
            
            normalized.append(output_path)
            print(f"  ✓ {filepath} → {output_path}")
    
    return normalized


def create_master_summary(normalized_dir: Path, output_path: Path):
    """Create a master summary of all normalized results."""
    all_results = []
    
    for filepath in normalized_dir.glob("*.json"):
        try:
            with open(filepath) as f:
                data = json.load(f)
            all_results.append(data)
        except Exception:
            pass
    
    if not all_results:
        print("No results to summarize", file=sys.stderr)
        return
    
    # Organize by benchmark and language
    summary = {
        "generated_at": datetime.now().isoformat(),
        "total_benchmarks": len(all_results),
        "benchmarks": {},
    }
    
    for result in all_results:
        bench_name = result.get("benchmark", "unknown")
        lang = result.get("language", "unknown")
        mode = result.get("execution_mode", "unknown")
        
        if bench_name not in summary["benchmarks"]:
            summary["benchmarks"][bench_name] = {}
        
        if mode not in summary["benchmarks"][bench_name]:
            summary["benchmarks"][bench_name][mode] = {}
        
        summary["benchmarks"][bench_name][mode][lang] = {
            "min_time_ms": result.get("min_time_ms"),
            "mean_time_ms": result.get("mean_time_ms"),
            "std_time_ms": result.get("std_time_ms"),
            "runs": result.get("runs"),
        }
    
    with open(output_path, "w") as f:
        json.dump(summary, f, indent=2)
    
    print(f"\n✓ Master summary: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Normalize benchmark results to unified format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    %(prog)s --input results/ --output results/normalized/
    %(prog)s --file results/warm_start/vector_python_warm.json --output-dir results/normalized/
    %(prog)s --input results/ --summary  # Also create master summary
        """,
    )
    parser.add_argument("--input", "-i", help="Input directory with results")
    parser.add_argument("--file", "-f", help="Single file to normalize")
    parser.add_argument("--output", "-o", help="Output directory")
    parser.add_argument("--output-dir", help="Output directory (alternative)")
    parser.add_argument("--summary", "-s", action="store_true", help="Create master summary")
    
    args = parser.parse_args()
    
    output_dir = Path(args.output or args.output_dir or "results/normalized")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if args.file:
        # Single file mode
        filepath = Path(args.file)
        data = normalize_file(filepath)
        if data:
            benchmark = data.get("benchmark", "unknown")
            language = data.get("language", "unknown")
            mode = data.get("execution_mode", "unknown")
            
            output_path = output_dir / f"{benchmark}_{language}_{mode}.json"
            with open(output_path, "w") as f:
                json.dump(data, f, indent=2)
            
            print(f"✓ Normalized: {output_path}")
        else:
            print(f"✗ Failed to normalize {filepath}", file=sys.stderr)
            return 1
    
    elif args.input:
        # Batch mode
        input_dir = Path(args.input)
        print(f"Normalizing results from {input_dir}...")
        
        normalized = normalize_directory(input_dir, output_dir)
        
        if normalized:
            print(f"\n✓ Normalized {len(normalized)} results to {output_dir}")
            
            if args.summary:
                summary_path = output_dir / "master_summary.json"
                create_master_summary(output_dir, summary_path)
        else:
            print("No results found to normalize", file=sys.stderr)
            return 1
    
    else:
        parser.print_help()
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
