#!/usr/bin/env python3
"""
Generate publication-quality visualizations for thesis benchmark results.

Creates comparative charts, performance profiles, and statistical summaries.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Any
import argparse
import warnings
warnings.filterwarnings('ignore')


def load_normalized_results(results_dir: Path) -> List[Dict[str, Any]]:
    """Load normalized results from directory."""
    normalized_file = results_dir / "normalized" / "normalized_results.json"
    if not normalized_file.exists():
        print(f"Error: Normalized results not found at {normalized_file}")
        print("Run normalize_results.py first!")
        sys.exit(1)

    with open(normalized_file, 'r') as f:
        return json.load(f)


def create_performance_comparison_chart(results: List[Dict[str, Any]], output_dir: Path):
    """Create performance comparison bar chart."""
    try:
        import matplotlib.pyplot as plt
        import numpy as np
        import pandas as pd
    except ImportError:
        print("Warning: matplotlib/pandas not available, skipping chart")
        return

    # Deduplicate: keep best (fastest) result per benchmark/language/sub-benchmark
    best = {}
    for r in results:
        bench = r["benchmark"]
        lang = r["language"]
        sub = r.get("sub_benchmark", "")
        if not bench or not lang:
            continue
        key = (bench, lang, sub)
        t = r["min_time_s"]
        if key not in best or t < best[key]["min_time_s"]:
            best[key] = r

    # Group by benchmark, average across sub-benchmarks per language
    bench_lang_data = {}
    for (bench, lang, sub), r in best.items():
        if bench not in bench_lang_data:
            bench_lang_data[bench] = {}
        if lang not in bench_lang_data[bench]:
            bench_lang_data[bench][lang] = []
        bench_lang_data[bench][lang].append(r["min_time_s"])

    # For each benchmark/language, use the minimum across all sub-benchmarks
    for bench in bench_lang_data:
        for lang in bench_lang_data[bench]:
            bench_lang_data[bench][lang] = min(bench_lang_data[bench][lang])

    # Prepare data for plotting
    benchmarks = sorted(bench_lang_data.keys())
    languages = ["Python", "Julia", "R"]

    python_times = [bench_lang_data.get(b, {}).get("Python", 0) for b in benchmarks]
    julia_times = [bench_lang_data.get(b, {}).get("Julia", 0) for b in benchmarks]
    r_times = [bench_lang_data.get(b, {}).get("R", 0) for b in benchmarks]

    bar_width = 0.25
    r1 = np.arange(len(benchmarks))
    r2 = [x + bar_width for x in r1]
    r3 = [x + bar_width for x in r2]

    fig, ax = plt.subplots(figsize=(12, 8))
    ax.bar(r1, python_times, color='blue', width=bar_width, edgecolor='grey', label='Python')
    ax.bar(r2, julia_times, color='orange', width=bar_width, edgecolor='grey', label='Julia')
    ax.bar(r3, r_times, color='green', width=bar_width, edgecolor='grey', label='R')

    ax.set_xlabel('Benchmark Scenarios', fontweight='bold')
    ax.set_ylabel('Minimum Time (seconds)', fontweight='bold')
    ax.set_title('Performance Comparison Across Language Implementations\n(Minimum Time as Primary Estimator)')
    ax.set_xticks([r + bar_width for r in range(len(benchmarks))])
    ax.set_xticklabels(benchmarks, rotation=45, ha='right')
    ax.legend()
    ax.grid(True, alpha=0.3)

    output_dir.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(output_dir / "performance_comparison.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved performance_comparison.png")


def create_speedup_heatmap(results: List[Dict[str, Any]], output_dir: Path):
    """Create heatmap showing speedup ratios relative to fastest per benchmark."""
    try:
        import matplotlib.pyplot as plt
        import seaborn as sns
        import numpy as np
        import pandas as pd
    except ImportError:
        print("Warning: matplotlib/seaborn not available, skipping heatmap")
        return

    # Deduplicate: best per benchmark/language
    best = {}
    for r in results:
        bench = r["benchmark"]
        lang = r["language"]
        if not bench or not lang:
            continue
        key = (bench, lang)
        t = r["min_time_s"]
        if key not in best or t < best[key]:
            best[key] = t

    # Find baseline (fastest per benchmark across all languages)
    bench_baseline = {}
    for (bench, lang), t in best.items():
        if bench not in bench_baseline or t < bench_baseline[bench]:
            bench_baseline[bench] = t

    # Calculate speedups
    speedup_data = []
    for (bench, lang), t in best.items():
        baseline = bench_baseline[bench]
        speedup = baseline / t if t > 0 else 0
        speedup_data.append({"Benchmark": bench, "Language": lang, "Speedup": speedup})

    df = pd.DataFrame(speedup_data)
    pivot_df = df.pivot(index="Language", columns="Benchmark", values="Speedup")

    plt.figure(figsize=(12, 6))
    sns.heatmap(pivot_df, annot=True, fmt=".2f", cmap="RdYlGn",
                cbar_kws={'label': 'Speedup Factor'})
    plt.title("Relative Performance Speedup\n(1.00 = fastest, higher = slower)")
    plt.xlabel("Benchmark Scenarios")
    plt.ylabel("Programming Languages")
    plt.tight_layout()

    output_dir.mkdir(parents=True, exist_ok=True)
    plt.savefig(output_dir / "speedup_heatmap.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Saved speedup_heatmap.png")


def create_summary_report(results: List[Dict[str, Any]], output_dir: Path):
    """Create textual summary report with deduplicated rankings."""
    # Deduplicate: best per benchmark/language
    best = {}
    for r in results:
        bench = r["benchmark"]
        lang = r["language"]
        if not bench or not lang:
            continue
        key = (bench, lang)
        t = r["min_time_s"]
        if key not in best or t < best[key]["min_time_s"]:
            best[key] = r

    # Group by benchmark
    bench_results = {}
    for (bench, lang), r in best.items():
        if bench not in bench_results:
            bench_results[bench] = []
        bench_results[bench].append(r)

    # Generate report
    report_lines = [
        "=" * 80,
        "THESIS BENCHMARK RESULTS SUMMARY",
        "=" * 80,
        "",
        "Performance Rankings (by minimum time, deduplicated):",
        "-" * 50,
        ""
    ]

    for bench in sorted(bench_results.keys()):
        bench_data = bench_results[bench]
        sorted_data = sorted(bench_data, key=lambda x: x["min_time_s"])

        report_lines.append(f"  {bench.replace('_', ' ').title()}:")
        for i, result in enumerate(sorted_data, 1):
            lang = result["language"]
            min_time = result["min_time_s"]
            mean_time = result["mean_time_s"]
            std_time = result["std_time_s"]
            report_lines.append(
                f"    {i}. {lang}: {min_time:.4f}s "
                f"(mean: {mean_time:.4f}s, std: {std_time:.4f}s)"
            )
        report_lines.append("")

    # Summary table
    report_lines.extend([
        "",
        "Summary Statistics:",
        "-" * 50,
        "",
        f"{'Benchmark':<20} {'Python':>10} {'Julia':>10} {'R':>10}",
        "-" * 50,
    ])

    for bench in sorted(bench_results.keys()):
        times = {}
        for r in bench_results[bench]:
            times[r["language"]] = r["min_time_s"]
        row = f"{bench:<20} {times.get('Python', 0):>10.4f} {times.get('Julia', 0):>10.4f} {times.get('R', 0):>10.4f}"
        report_lines.append(row)

    # Save
    output_dir.mkdir(parents=True, exist_ok=True)
    report_file = output_dir / "benchmark_summary.md"
    with open(report_file, 'w') as f:
        f.write('\n'.join(report_lines))
    print(f"  ✓ Saved benchmark_summary.md")


def main():
    parser = argparse.ArgumentParser(description="Generate thesis benchmark visualizations")
    parser.add_argument("--input", "-i", type=Path, default=None,
                       help="Input directory containing results")
    parser.add_argument("--output", "-o", type=Path, default=None,
                       help="Output directory for figures")
    parser.add_argument("--all", "-a", action="store_true",
                       help="Generate all visualizations")

    args = parser.parse_args()

    # Resolve paths relative to project root
    project_root = Path(__file__).parent.parent
    if args.input is None:
        args.input = project_root / "results"
    if args.output is None:
        args.output = project_root / "results" / "figures"

    print("=" * 60)
    print("GENERATING THESIS BENCHMARK VISUALIZATIONS")
    print("=" * 60)
    print(f"Input directory: {args.input}")
    print(f"Output directory: {args.output}")
    print()

    # Load results
    try:
        results = load_normalized_results(args.input)
        print(f"Loaded {len(results)} benchmark entries")
    except Exception as e:
        print(f"Error loading results: {e}")
        return 1

    # Filter out zero-time entries (likely parsing errors)
    valid = [r for r in results if r["min_time_s"] > 0 and r["benchmark"]]
    if len(valid) < len(results):
        print(f"Filtered {len(results) - len(valid)} invalid entries (zero time or no benchmark)")
    results = valid
    print(f"Using {len(results)} valid entries")
    print()

    # Generate visualizations
    create_performance_comparison_chart(results, args.output)
    create_speedup_heatmap(results, args.output)
    create_summary_report(results, args.output)

    print("\n✓ Visualization generation complete!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
