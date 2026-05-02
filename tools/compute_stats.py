#!/usr/bin/env python3
"""
Post-processing statistics engine for benchmark results.

Computes advanced statistical metrics from raw timing arrays:
- Bootstrap confidence intervals for minimum (Chen & Revels 2016)
- Shapiro-Wilk normality tests
- Coefficient of variation (CV)
- Cohen's d effect sizes for cross-language comparisons
- Flaky benchmark detection (CV > 10%)

Follows Chen & Revels (2016): "Robust benchmarking in noisy environments"
"""

import json
import sys
import numpy as np
from pathlib import Path
from typing import Dict, List, Any, Optional
import argparse


def bootstrap_ci_min(times: List[float], n_resamples: int = 1000,
                     confidence: float = 0.95) -> Dict[str, float]:
    """
    Compute bootstrap confidence interval for the minimum.

    Following Chen & Revels (2016), the minimum is the primary estimator.
    This computes a bootstrap CI around the minimum by resampling with
    replacement and taking the minimum of each resample.

    Args:
        times: Raw timing array from benchmark runs
        n_resamples: Number of bootstrap resamples (default 1000)
        confidence: Confidence level (default 0.95 for 95% CI)

    Returns:
        Dict with 'min', 'ci_lower', 'ci_upper', 'ci_width'
    """
    if len(times) < 2:
        return {
            "min": times[0] if times else 0.0,
            "ci_lower": times[0] if times else 0.0,
            "ci_upper": times[0] if times else 0.0,
            "ci_width": 0.0,
        }

    times_arr = np.array(times, dtype=np.float64)
    observed_min = float(np.min(times_arr))

    bootstrap_mins = np.zeros(n_resamples)
    rng = np.random.default_rng(42)
    for i in range(n_resamples):
        resample = rng.choice(times_arr, size=len(times_arr), replace=True)
        bootstrap_mins[i] = np.min(resample)

    alpha = 1.0 - confidence
    ci_lower = float(np.percentile(bootstrap_mins, 100 * alpha / 2))
    ci_upper = float(np.percentile(bootstrap_mins, 100 * (1 - alpha / 2)))

    return {
        "min": observed_min,
        "ci_lower": ci_lower,
        "ci_upper": ci_upper,
        "ci_width": ci_upper - ci_lower,
    }


def shapiro_wilk_test(times: List[float]) -> Dict[str, Any]:
    """
    Perform Shapiro-Wilk normality test on timing data.

    Args:
        times: Raw timing array (needs 3+ observations)

    Returns:
        Dict with 'statistic', 'p_value', 'is_normal' (alpha=0.05)
    """
    from scipy import stats

    if len(times) < 3:
        return {
            "statistic": None,
            "p_value": None,
            "is_normal": None,
            "note": "insufficient data (need >= 3 samples)",
        }

    if len(times) > 5000:
        return {
            "statistic": None,
            "p_value": None,
            "is_normal": None,
            "note": "too many samples for Shapiro-Wilk (max 5000)",
        }

    stat, p_value = stats.shapiro(times)

    return {
        "statistic": float(stat),
        "p_value": float(p_value),
        "is_normal": bool(p_value > 0.05),
    }


def compute_cv(times: List[float]) -> Dict[str, float]:
    """
    Compute coefficient of variation (CV = std / mean).

    CV > 10% indicates potentially flaky benchmark.

    Args:
        times: Raw timing array

    Returns:
        Dict with 'cv', 'is_flaky'
    """
    if len(times) < 2:
        return {"cv": 0.0, "is_flaky": False}

    times_arr = np.array(times)
    mean_t = float(np.mean(times_arr))
    std_t = float(np.std(times_arr))

    if mean_t <= 0:
        return {"cv": 0.0, "is_flaky": False}

    cv = std_t / mean_t

    return {
        "cv": cv,
        "is_flaky": cv > 0.10,
    }


def cohens_d(group1: List[float], group2: List[float]) -> Dict[str, float]:
    """
    Compute Cohen's d effect size between two groups.

    Uses pooled standard deviation (Hedges' g correction for small samples).

    Args:
        group1: Timing array for first language
        group2: Timing array for second language

    Returns:
        Dict with 'd', 'magnitude' (small/medium/large)
    """
    if len(group1) < 2 or len(group2) < 2:
        return {"d": 0.0, "magnitude": "undefined"}

    g1 = np.array(group1, dtype=np.float64)
    g2 = np.array(group2, dtype=np.float64)

    n1, n2 = len(g1), len(g2)
    mean1, mean2 = float(np.mean(g1)), float(np.mean(g2))

    var1 = np.var(g1, ddof=1)
    var2 = np.var(g2, ddof=1)

    pooled_std = np.sqrt(((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2))

    if pooled_std == 0:
        return {"d": 0.0, "magnitude": "no difference"}

    d = (mean1 - mean2) / pooled_std

    abs_d = abs(d)
    if abs_d < 0.2:
        magnitude = "negligible"
    elif abs_d < 0.5:
        magnitude = "small"
    elif abs_d < 0.8:
        magnitude = "medium"
    else:
        magnitude = "large"

    return {
        "d": float(d),
        "magnitude": magnitude,
    }


def process_single_result(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Compute statistics for a single result entry with raw timing data.

    Args:
        data: Dict containing 'times' array and other metadata

    Returns:
        Dict with added statistical metrics
    """
    result = dict(data)
    times = data.get("times", [])

    if not times:
        result["stats_note"] = "no raw timing data available"
        return result

    bootstrap = bootstrap_ci_min(times)
    normality = shapiro_wilk_test(times)
    cv_result = compute_cv(times)

    result["bootstrap_min_ci"] = bootstrap
    result["ci_95_lower"] = bootstrap["ci_lower"]
    result["ci_95_upper"] = bootstrap["ci_upper"]
    result["normality"] = normality
    result["cv"] = cv_result["cv"]
    result["is_flaky"] = cv_result["is_flaky"]

    return result


def compute_cross_language_effect_sizes(
    results: List[Dict[str, Any]],
    benchmark: str,
    sub_benchmark: str,
) -> Dict[str, Dict[str, Any]]:
    """
    Compute Cohen's d effect sizes between all language pairs for a benchmark.

    Args:
        results: List of normalized result entries
        benchmark: Benchmark name to filter on
        sub_benchmark: Sub-benchmark name to filter on

    Returns:
        Dict mapping language pairs to effect size results
    """
    filtered = [
        r for r in results
        if r.get("benchmark") == benchmark
        and r.get("sub_benchmark") == sub_benchmark
        and "times" in r and r["times"]
    ]

    by_lang: Dict[str, List[float]] = {}
    for r in filtered:
        lang = r.get("language", "unknown")
        by_lang.setdefault(lang, []).extend(r["times"])

    effect_sizes = {}
    langs = sorted(by_lang.keys())

    for i in range(len(langs)):
        for j in range(i + 1, len(langs)):
            pair = f"{langs[i]}_vs_{langs[j]}"
            effect_sizes[pair] = cohens_d(by_lang[langs[i]], by_lang[langs[j]])

    return effect_sizes


def process_all_results(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Process all results: per-entry stats + cross-language effect sizes.

    Args:
        results: List of normalized result entries

    Returns:
        Dict with 'entries' (processed), 'effect_sizes', 'flaky_warnings', 'summary'
    """
    processed_entries = []
    flaky_warnings = []

    for entry in results:
        processed = process_single_result(entry)
        processed_entries.append(processed)

        if processed.get("is_flaky", False):
            flaky_warnings.append({
                "benchmark": processed.get("benchmark", ""),
                "sub_benchmark": processed.get("sub_benchmark", ""),
                "language": processed.get("language", ""),
                "cv": processed["cv"],
            })

    bench_subs = set()
    for e in processed_entries:
        bench_subs.add((e.get("benchmark", ""), e.get("sub_benchmark", "")))

    effect_sizes = {}
    for benchmark, sub_benchmark in sorted(bench_subs):
        if not benchmark:
            continue
        es = compute_cross_language_effect_sizes(
            processed_entries, benchmark, sub_benchmark
        )
        if es:
            key = f"{benchmark}/{sub_benchmark}" if sub_benchmark else benchmark
            effect_sizes[key] = es

    summary = {
        "total_entries": len(processed_entries),
        "flaky_count": len(flaky_warnings),
        "benchmarks_processed": len(bench_subs),
        "effect_size_comparisons": sum(len(v) for v in effect_sizes.values()),
    }

    return {
        "entries": processed_entries,
        "effect_sizes": effect_sizes,
        "flaky_warnings": flaky_warnings,
        "summary": summary,
    }


def load_results(input_path: Path) -> List[Dict[str, Any]]:
    """
    Load results from a normalized_results.json or individual JSON files.

    Args:
        input_path: Path to file or directory

    Returns:
        List of result dicts
    """
    if input_path.is_file():
        with open(input_path, "r") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
        elif isinstance(data, dict) and "entries" in data:
            return data["entries"]
        return [data]

    results = []
    for json_file in sorted(input_path.glob("*.json")):
        if json_file.name == "normalized_results.json":
            continue
        if json_file.name == "summary.json":
            continue
        try:
            with open(json_file, "r") as f:
                data = json.load(f)
            if isinstance(data, list):
                results.extend(data)
            elif isinstance(data, dict):
                if "times" in data:
                    results.append(data)
                elif "results" in data and isinstance(data["results"], dict):
                    for sub_name, sub_data in data["results"].items():
                        if isinstance(sub_data, dict):
                            entry = dict(data)
                            entry["sub_benchmark"] = sub_name
                            entry.update(sub_data)
                            results.append(entry)
        except Exception as e:
            print(f"Warning: Could not process {json_file}: {e}", file=sys.stderr)

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Compute advanced statistics from benchmark results"
    )
    parser.add_argument(
        "--input", "-i", type=Path, default=None,
        help="Input file (normalized_results.json) or directory"
    )
    parser.add_argument(
        "--output", "-o", type=Path, default=None,
        help="Output file for processed results"
    )
    parser.add_argument(
        "--n-resamples", type=int, default=1000,
        help="Number of bootstrap resamples (default: 1000)"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Print detailed output"
    )

    args = parser.parse_args()

    project_root = Path(__file__).parent.parent
    if args.input is None:
        normalized = project_root / "results" / "normalized" / "normalized_results.json"
        if normalized.exists():
            args.input = normalized
        else:
            args.input = project_root / "results"

    if args.output is None:
        args.output = project_root / "results" / "stats_results.json"

    print("=" * 60)
    print("BENCHMARK STATISTICS ENGINE")
    print("=" * 60)
    print(f"Input: {args.input}")
    print(f"Output: {args.output}")
    print(f"Bootstrap resamples: {args.n_resamples}")
    print()

    results = load_results(args.input)

    if not results:
        print("No results found to process!")
        return 1

    print(f"Loaded {len(results)} result entries")
    print("Processing...")

    stats = process_all_results(results)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(stats, f, indent=2)

    print(f"\nSaved statistics to {args.output}")

    summary = stats["summary"]
    print(f"\nSUMMARY:")
    print(f"  Total entries processed: {summary['total_entries']}")
    print(f"  Flaky benchmarks (CV > 10%): {summary['flaky_count']}")
    print(f"  Effect size comparisons: {summary['effect_size_comparisons']}")

    if stats["flaky_warnings"]:
        print(f"\nFLAKY BENCHMARKS (CV > 10%):")
        for w in stats["flaky_warnings"]:
            print(f"  {w['language']} {w['benchmark']}/{w['sub_benchmark']}: CV = {w['cv']:.2%}")

    if stats["effect_sizes"] and args.verbose:
        print(f"\nCROSS-LANGUAGE EFFECT SIZES (Cohen's d):")
        for bench, pairs in stats["effect_sizes"].items():
            print(f"  {bench}:")
            for pair, es in pairs.items():
                print(f"    {pair}: d = {es['d']:.3f} ({es['magnitude']})")

    print("\nStatistics computation complete!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
