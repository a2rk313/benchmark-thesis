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
        print("Warning: matplotlib/pandas not available, skipping visualization")
        return
    
    # Group results by benchmark and language
    bench_lang_data = {}
    for result in results:
        bench = result["benchmark"]
        lang = result["language"]
        min_time = result["min_time_s"]
        
        if bench not in bench_lang_data:
            bench_lang_data[bench] = {}
        bench_lang_data[bench][lang] = min_time
    
    # Create chart
    fig, ax = plt.subplots(figsize=(12, 8))
    
    # Prepare data for plotting
    benchmarks = list(bench_lang_data.keys())
    languages = ["Python", "Julia", "R"]
    
    # Collect data
    python_times = [bench_lang_data.get(bench, {}).get("Python", 0) for bench in benchmarks]
    julia_times = [bench_lang_data.get(bench, {}).get("Julia", 0) for bench in benchmarks]
    r_times = [bench_lang_data.get(bench, {}).get("R", 0) for bench in benchmarks]
    
    # Set width of bars
    bar_width = 0.25
    r1 = np.arange(len(benchmarks))
    r2 = [x + bar_width for x in r1]
    r3 = [x + bar_width for x in r2]
    
    # Plot bars
    bars1 = ax.bar(r1, python_times, color='blue', width=bar_width, edgecolor='grey', label='Python')
    bars2 = ax.bar(r2, julia_times, color='orange', width=bar_width, edgecolor='grey', label='Julia')
    bars3 = ax.bar(r3, r_times, color='green', width=bar_width, edgecolor='grey', label='R')
    
    # Add labels and title
    ax.set_xlabel('Benchmark Scenarios', fontweight='bold')
    ax.set_ylabel('Time (seconds)', fontweight='bold')
    ax.set_title('Performance Comparison Across Language Implementations\n(Minimum Time as Primary Estimator)')
    ax.set_xticks([r + bar_width for r in range(len(benchmarks))])
    ax.set_xticklabels(benchmarks, rotation=45, ha='right')
    ax.legend()
    
    # Add grid
    ax.grid(True, alpha=0.3)
    
    # Save plot
    output_dir.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(output_dir / "performance_comparison.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Saved performance comparison chart to {output_dir / 'performance_comparison.png'}")

def create_speedup_heatmap(results: List[Dict[str, Any]], output_dir: Path):
    """Create heatmap showing speedup ratios."""
    try:
        import matplotlib.pyplot as plt
        import seaborn as sns
        import numpy as np
        import pandas as pd
    except ImportError:
        print("Warning: matplotlib/seaborn not available, skipping heatmap")
        return
    
    # Find baseline (fastest implementation per benchmark)
    bench_baseline = {}
    for result in results:
        bench = result["benchmark"]
        min_time = result["min_time_s"]
        
        if bench not in bench_baseline or min_time < bench_baseline[bench]:
            bench_baseline[bench] = min_time
    
    # Calculate speedups
    speedup_data = []
    for result in results:
        bench = result["benchmark"]
        lang = result["language"]
        min_time = result["min_time_s"]
        baseline = bench_baseline[bench]
        speedup = baseline / min_time if min_time > 0 else 0
        speedup_data.append({"Benchmark": bench, "Language": lang, "Speedup": speedup})
    
    # Create DataFrame and pivot
    df = pd.DataFrame(speedup_data)
    pivot_df = df.pivot(index="Language", columns="Benchmark", values="Speedup")
    
    # Create heatmap
    plt.figure(figsize=(12, 6))
    sns.heatmap(pivot_df, annot=True, fmt=".2f", cmap="RdYlGn", cbar_kws={'label': 'Speedup Factor'})
    plt.title("Relative Performance Speedup (Higher = Faster)")
    plt.xlabel("Benchmark Scenarios")
    plt.ylabel("Programming Languages")
    plt.tight_layout()
    
    # Save plot
    output_dir.mkdir(parents=True, exist_ok=True)
    plt.savefig(output_dir / "speedup_heatmap.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Saved speedup heatmap to {output_dir / 'speedup_heatmap.png'}")

def create_summary_report(results: List[Dict[str, Any]], output_dir: Path):
    """Create textual summary report."""
    # Group results by benchmark
    bench_results = {}
    for result in results:
        bench = result["benchmark"]
        if bench not in bench_results:
            bench_results[bench] = []
        bench_results[bench].append(result)
    
    # Generate report
    report_lines = [
        "=" * 80,
        "THESIS BENCHMARK RESULTS SUMMARY",
        "=" * 80,
        "",
        "Performance Rankings (by minimum time):",
        "-" * 40,
        ""
    ]
    
    for bench, bench_data in bench_results.items():
        # Sort by minimum time
        sorted_data = sorted(bench_data, key=lambda x: x["min_time_s"])
        
        report_lines.append(f"{bench.replace('_', ' ').title()}:")
        for i, result in enumerate(sorted_data, 1):
            lang = result["language"]
            min_time = result["min_time_s"]
            report_lines.append(f"  {i}. {lang}: {min_time:.4f}s")
        report_lines.append("")
    
    # Save report
    output_dir.mkdir(parents=True, exist_ok=True)
    report_file = output_dir / "benchmark_summary.md"
    with open(report_file, 'w') as f:
        f.write('\n'.join(report_lines))
    print(f"Saved summary report to {report_file}")

def main():
    parser = argparse.ArgumentParser(description="Generate thesis benchmark visualizations")
    parser.add_argument("--input", "-i", type=Path, default=Path("results"),
                       help="Input directory containing results")
    parser.add_argument("--output", "-o", type=Path, default=Path("results/figures"),
                       help="Output directory for figures")
    parser.add_argument("--all", "-a", action="store_true",
                       help="Generate all visualizations")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("GENERATING THESIS BENCHMARK VISUALIZATIONS")
    print("=" * 60)
    print(f"Input directory: {args.input}")
    print(f"Output directory: {args.output}")
    print()
    
    # Load results
    try:
        results = load_normalized_results(args.input)
        print(f"Loaded {len(results)} benchmark results")
    except Exception as e:
        print(f"Error loading results: {e}")
        return 1
    
    # Generate visualizations
    if args.all or True:  # Always generate basic visualizations
        create_performance_comparison_chart(results, args.output)
        create_speedup_heatmap(results, args.output)
        create_summary_report(results, args.output)
    
    print("\n✓ Visualization generation complete!")
    return 0

if __name__ == "__main__":
    sys.exit(main())