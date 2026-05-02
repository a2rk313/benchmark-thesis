#!/usr/bin/env python3
"""
Normalize benchmark results from different sources into a unified format.

This resolves the issue of mixed container vs native result formats and
ensures consistent data structures for visualization and analysis.

Handles 4 distinct result file formats:
  1. Standard:    {"results": {"sub_bench": {"min": 1.0, "mean": 2.0, ...}}}
  2. R flat:      {"csv_write": {"min": 0.5}, "csv_read": {"min": 0.2}}  (no "results" key)
  3. Single flat: {"min_time_s": 0.014, "mean_time_s": 0.02, ...}
  4. Nested subs: {"mercator_1000": {"min_time_s": 0.0005}, "utm_1000": {...}}
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Any
import argparse

METADATA_KEYS = {
    "language", "numpy_version", "matrix_size", "n_runs", "n_warmup",
    "methodology", "n_csv_rows", "n_binary_values", "julia_version",
    "sorting_size", "r_version", "blas_library", "scenario",
    "zone_type", "n_zones", "polygons", "min_time_s", "mean_time_s",
    "std_time_s", "median_time_s", "max_time_s", "hash", "n_dates", "warmup", "runs",
    "library", "ci_95_lower", "ci_95_upper", "cv", "memory_rss_mb",
    "memory_vms_mb", "validation_hash", "all_hashes", "combined_hash",
    "n_points", "n_matches", "n_matched", "matches_found",
    "n_polygons", "pixels_processed", "chunks_processed", "n_bands",
    "mean_sam_rad", "std_sam_rad", "min_sam_rad", "max_sam_rad", "mean_sam_deg",
    "total_distance_m", "mean_distance_m", "median_distance_m", "max_distance_m",
    "n_points_interp", "grid_size", "total_interpolated", "points_per_second",
    "mean_value", "std_value", "median_value",
    "mean_ndvi", "mean_trend", "mean_amplitude", "avg_growing_season",
    "points_per_second", "normality_p", "is_normal", "ci_95", "peak_memory_mb",
    "reference_hash", "times", "validation_hashes",
}

TIMING_KEYS = {"min", "mean", "std", "median", "max", "min_time_s", "mean_time_s",
               "std_time_s", "median_time_s", "max_time_s", "times"}


def _unwrap(val):
    """Unwrap single-element lists from R's auto_unbox=FALSE serialization."""
    if isinstance(val, list) and len(val) == 1:
        return val[0]
    return val


def _safe_float(val, default=0.0):
    """Safely convert a value to float, handling R list-wrapped values."""
    if val is None:
        return default
    val = _unwrap(val)
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def _safe_int(val, default=0):
    """Safely convert a value to int, handling R list-wrapped values."""
    if val is None:
        return default
    val = _unwrap(val)
    try:
        return int(val)
    except (TypeError, ValueError):
        return default


def _has_timing(sub_data):
    """Check if a dict contains any timing keys with non-None values."""
    if not isinstance(sub_data, dict):
        return False
    for k in TIMING_KEYS:
        v = _unwrap(sub_data.get(k))
        if v is not None:
            return True
    return False


def _extract_benchmark_from_filename(filename):
    """Extract benchmark name and scenario from filename."""
    fn = filename.lower()
    if "matrix" in fn:
        return "matrix_ops", "matrix_operations"
    elif "io_ops" in fn or ("io" in fn and "ops" in fn):
        return "io_ops", "io_operations"
    elif "vector" in fn:
        return "vector_pip", "vector_point_in_polygon"
    elif "hsi" in fn or "hyperspectral" in fn:
        return "hsi_stream", "hyperspectral_sam"
    elif "interpolation" in fn or "idw" in fn:
        return "interpolation_idw", "spatial_interpolation"
    elif "timeseries" in fn or "ndvi" in fn:
        return "timeseries_ndvi", "time_series_ndvi"
    elif "reprojection" in fn:
        return "reprojection", "coordinate_reprojection"
    elif "zonal" in fn:
        return "zonal_stats", "zonal_statistics"
    elif "raster" in fn:
        return "raster_algebra", "raster_algebra"
    elif "scaling" in fn:
        return "scaling", "scaling_analysis"
    return "", ""


def _extract_language(data, filename):
    """Extract language from data dict or filename."""
    lang = data.get("language")
    if lang:
        if isinstance(lang, list):
            lang = lang[0] if lang else ""
        lang = str(lang).strip()
        if lang:
            return lang.capitalize()
    fn = filename.lower()
    if "python" in fn:
        return "Python"
    elif "julia" in fn:
        return "Julia"
    elif fn.endswith("_r.json") or fn.startswith("r_") or "_r." in fn:
        return "R"
    return ""


def _make_entry(sub_name, sub_data, default_bench, default_scenario,
                default_lang, source_file, mode):
    """Create a normalized entry from a sub-benchmark dict."""
    entry = {
        "language": default_lang,
        "benchmark": default_bench,
        "scenario": default_scenario,
        "sub_benchmark": sub_name,
        "min_time_s": 0.0,
        "mean_time_s": 0.0,
        "median_time_s": 0.0,
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
        "source_file": source_file,
        "mode": mode,
    }

    entry["min_time_s"] = _safe_float(_unwrap(sub_data.get("min_time_s", sub_data.get("min"))))
    entry["mean_time_s"] = _safe_float(_unwrap(sub_data.get("mean_time_s", sub_data.get("mean"))))
    entry["median_time_s"] = _safe_float(_unwrap(sub_data.get("median_time_s", sub_data.get("median"))))
    entry["std_time_s"] = _safe_float(_unwrap(sub_data.get("std_time_s", sub_data.get("std"))))
    entry["max_time_s"] = _safe_float(_unwrap(sub_data.get("max_time_s", sub_data.get("max"))))

    ci95 = sub_data.get("ci_95")
    if ci95 is not None and isinstance(ci95, list) and len(ci95) >= 2:
        entry["ci_95_lower"] = _safe_float(ci95[0])
        entry["ci_95_upper"] = _safe_float(ci95[1])
    else:
        entry["ci_95_lower"] = _safe_float(sub_data.get("ci_95_lower"), entry["ci_95_lower"])
        entry["ci_95_upper"] = _safe_float(sub_data.get("ci_95_upper"), entry["ci_95_upper"])

    if entry["mean_time_s"] > 0:
        entry["cv"] = entry["std_time_s"] / entry["mean_time_s"]

    entry["runs"] = _safe_int(sub_data.get("runs"), _safe_int(sub_data.get("n_runs"), 0))
    entry["warmup"] = _safe_int(sub_data.get("warmup"), _safe_int(sub_data.get("n_warmup"), 0))

    entry["memory_rss_mb"] = _unwrap(sub_data.get("memory_rss_mb"))
    entry["memory_vms_mb"] = _unwrap(sub_data.get("memory_vms_mb"))

    entry["validation_hash"] = str(_unwrap(sub_data.get("validation_hash", sub_data.get("hash", ""))))

    matched = _safe_int(sub_data.get("matches_found", sub_data.get("n_matches", sub_data.get("n_matched", 0))))
    if matched > 0:
        entry["matches_found"] = matched

    return entry


def normalize_single_result(result_path):
    """
    Normalize a single result file to unified format.

    Returns a list of entries (one per sub-benchmark).
    """
    try:
        with open(result_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Warning: Could not read {result_path}: {e}", file=sys.stderr)
        return []

    if not isinstance(data, dict):
        return []

    filename = result_path.name
    default_bench, default_scenario = _extract_benchmark_from_filename(filename)
    default_lang = _extract_language(data, filename)

    path_str = str(result_path)
    if "container" in path_str or "docker" in path_str or "podman" in path_str:
        mode = "container"
    elif "native" in path_str:
        mode = "native"
    else:
        mode = "unknown"

    entries = []

    # === Format 1: Standard with "results" key ===
    if "results" in data and isinstance(data["results"], dict):
        for sub_name, sub_data in data["results"].items():
            if _has_timing(sub_data):
                entries.append(_make_entry(
                    sub_name, sub_data, default_bench, default_scenario,
                    default_lang, str(result_path), mode
                ))

    # === Format 5: Hyperfine-style results (list) ===
    if not entries and "results" in data and isinstance(data["results"], list):
        for i, run_data in enumerate(data["results"]):
            if isinstance(run_data, dict) and _has_timing(run_data):
                sub_name = f"cold_start_{i}" if len(data["results"]) > 1 else "cold_start"
                entries.append(_make_entry(
                    sub_name, run_data, default_bench, default_scenario,
                    default_lang, str(result_path), mode
                ))

    # === Format 2/4: Flat sub-benchmarks at top level ===
    if not entries:
        has_sub_benchmarks = False
        for key, val in data.items():
            if key in METADATA_KEYS:
                continue
            if isinstance(val, dict) and _has_timing(val):
                has_sub_benchmarks = True
                entries.append(_make_entry(
                    key, val, default_bench, default_scenario,
                    default_lang, str(result_path), mode
                ))

        # === Format 3: Single flat entry ===
        if not has_sub_benchmarks:
            sub_data = {}
            for k in ["min_time_s", "mean_time_s", "std_time_s", "median_time_s", "max_time_s",
                       "min", "mean", "std", "median", "max", "hash", "validation_hash",
                       "ci_95", "ci_95_lower", "ci_95_upper", "runs", "warmup",
                       "n_runs", "n_warmup", "memory_rss_mb", "memory_vms_mb"]:
                if k in data:
                    sub_data[k] = _unwrap(data[k])
            if not sub_data:
                for key, val in data.items():
                    if key not in METADATA_KEYS:
                        sub_data[key] = _unwrap(val)
            scenario = _unwrap(data.get("scenario", default_bench))
            sub_name = str(scenario) if scenario else default_bench
            entries.append(_make_entry(
                sub_name, sub_data, default_bench, default_scenario,
                default_lang, str(result_path), mode
            ))

    return entries


def scan_and_normalize_results(input_dir):
    """Scan directory for result files and normalize them."""
    normalized_results = []
    found_files = set()

    direct_jsons = list(input_dir.glob("*.json"))
    has_direct_results = any(
        f.stem.endswith(("python", "julia", "r", "_results"))
        for f in direct_jsons if f.is_file()
    )

    if has_direct_results:
        patterns = ["*.json", "*/*.json", "*/*/*.json"]
    else:
        patterns = [
            "results/*.json",
            "results/*/*.json",
            "validation/*results.json",
            "*_results.json"
        ]

    skip_stems = {"hardware_info", "container_hashes", "errors",
                  "summary", "normalized_results"}

    for pattern in patterns:
        for file_path in input_dir.glob(pattern):
            if file_path.is_file() and file_path not in found_files:
                stem = file_path.stem
                if stem in skip_stems:
                    continue

                found_files.add(file_path)
                file_entries = normalize_single_result(file_path)
                normalized_results.extend(file_entries)

    return normalized_results


def generate_summary(normalized_results):
    """Generate summary statistics from normalized results."""
    summary = {
        "total_entries": len(normalized_results),
        "benchmarks": {},
        "languages": {},
    }

    for r in normalized_results:
        bench = r["benchmark"]
        lang = r["language"]
        sub = r.get("sub_benchmark", "")

        if bench not in summary["benchmarks"]:
            summary["benchmarks"][bench] = {"languages": {}, "sub_benchmarks": set()}
        if lang not in summary["benchmarks"][bench]["languages"]:
            summary["benchmarks"][bench]["languages"][lang] = 0
        summary["benchmarks"][bench]["languages"][lang] += 1
        if sub:
            summary["benchmarks"][bench]["sub_benchmarks"].add(sub)

        if lang not in summary["languages"]:
            summary["languages"][lang] = 0
        summary["languages"][lang] += 1

    for bench in summary["benchmarks"]:
        summary["benchmarks"][bench]["sub_benchmarks"] = \
            sorted(summary["benchmarks"][bench]["sub_benchmarks"])

    return summary


def main():
    parser = argparse.ArgumentParser(description="Normalize benchmark results")
    parser.add_argument("--input", "-i", type=Path, default=None,
                       help="Input directory to scan for results")
    parser.add_argument("--output", "-o", type=Path, default=None,
                       help="Output directory for normalized results")
    parser.add_argument("--summary", "-s", action="store_true",
                       help="Generate summary statistics")

    args = parser.parse_args()

    project_root = Path(__file__).parent.parent
    if args.input is None:
        args.input = project_root / "results"
    if args.output is None:
        args.output = project_root / "results" / "normalized"

    print("=" * 60)
    print("NORMALIZING BENCHMARK RESULTS")
    print("=" * 60)
    print(f"Input directory: {args.input}")
    print(f"Output directory: {args.output}")
    print()

    args.output.mkdir(parents=True, exist_ok=True)

    normalized_results = scan_and_normalize_results(args.input)

    if not normalized_results:
        print("No result files found!")
        return 1

    print(f"Found {len(normalized_results)} benchmark entries")

    benchmarks_seen = {}
    for r in normalized_results:
        bench = r["benchmark"]
        if bench not in benchmarks_seen:
            benchmarks_seen[bench] = set()
        lang = r["language"]
        sub = r.get("sub_benchmark", "")
        benchmarks_seen[bench].add(f"{lang} ({sub})" if sub else lang)

    print("\nBenchmarks found:")
    for bench in sorted(benchmarks_seen.keys()):
        langs = sorted(benchmarks_seen[bench])
        print(f"  {bench}: {', '.join(langs)}")
    print()

    output_file = args.output / "normalized_results.json"
    with open(output_file, 'w') as f:
        json.dump(normalized_results, f, indent=2)
    print(f"Saved normalized results to {output_file}")

    if args.summary:
        summary = generate_summary(normalized_results)
        summary_file = args.output / "summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        print(f"Saved summary to {summary_file}")

        print("\nSUMMARY:")
        print(f"  Total entries: {summary['total_entries']}")
        print("  By benchmark:")
        for bench, info in summary["benchmarks"].items():
            subs = info.get("sub_benchmarks", [])
            lang_counts = info.get("languages", {})
            subs_str = f" [{', '.join(subs)}]" if subs else ""
            langs_str = f" ({', '.join(f'{l}:{c}' for l,c in lang_counts.items())})"
            print(f"    {bench}{subs_str}{langs_str}")

    print("\nNormalization complete!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
