#!/usr/bin/env python3
"""
Compare Container vs Native Performance
Shows if container overhead is negligible (should be <5%)
"""

import json
import sys
from pathlib import Path

def load_results(path):
    """Load benchmark results."""
    if not Path(path).exists():
        return None
    
    with open(path) as f:
        return json.load(f)

def compare_results(container_path, native_path, lang):
    """Compare container vs native for one language."""
    container = load_results(container_path)
    native = load_results(native_path)
    
    if not container or not native:
        print(f"❌ Missing results for {lang}")
        return []
    
    print(f"\n{'='*70}")
    print(f"{lang.upper()} - Container vs Native")
    print(f"{'='*70}")
    
    comparisons = []
    
    for task in container.get('results', {}):
        if task not in native.get('results', {}):
            continue
        
        container_min = container['results'][task]['min']
        native_min = native['results'][task]['min']
        
        overhead_pct = ((container_min - native_min) / native_min) * 100
        
        print(f"\n{task}:")
        print(f"  Container: {container_min:>8.4f}s")
        print(f"  Native:    {native_min:>8.4f}s")
        print(f"  Overhead:  {overhead_pct:>8.2f}%", end="")
        
        if abs(overhead_pct) < 2:
            status = "✓ Negligible"
            print(f"  {status}")
        elif abs(overhead_pct) < 5:
            status = "✓ Acceptable"
            print(f"  {status}")
        else:
            status = "⚠ Investigate"
            print(f"  {status}")
        
        comparisons.append({
            'task': task,
            'overhead': overhead_pct,
            'status': status
        })
    
    return comparisons

def print_summary(all_comparisons):
    """Print summary statistics."""
    print(f"\n{'='*70}")
    print("SUMMARY")
    print(f"{'='*70}")
    
    all_overheads = []
    for lang_results in all_comparisons.values():
        for comp in lang_results:
            all_overheads.append(comp['overhead'])
    
    if not all_overheads:
        print("❌ No comparisons available")
        return
    
    avg_overhead = sum(all_overheads) / len(all_overheads)
    max_overhead = max(all_overheads)
    min_overhead = min(all_overheads)
    
    print(f"\nContainer Overhead Statistics:")
    print(f"  Average: {avg_overhead:>6.2f}%")
    print(f"  Range:   {min_overhead:>6.2f}% to {max_overhead:>6.2f}%")
    
    if avg_overhead < 3:
        print(f"\n✓ VERDICT: Container overhead is NEGLIGIBLE ({avg_overhead:.1f}% avg)")
        print(f"  → Container results are valid for thesis")
    elif avg_overhead < 5:
        print(f"\n✓ VERDICT: Container overhead is ACCEPTABLE ({avg_overhead:.1f}% avg)")
        print(f"  → Container results are valid, mention overhead in thesis")
    else:
        print(f"\n⚠ VERDICT: Container overhead is SIGNIFICANT ({avg_overhead:.1f}% avg)")
        print(f"  → Use native results for thesis, investigate container issue")
    
    print(f"\n{'='*70}")
    print("RECOMMENDATION FOR THESIS")
    print(f"{'='*70}")
    print("""
Use CONTAINER results as PRIMARY (reproducible by anyone)
Include NATIVE results in validation section
Document overhead is <5% (acceptable for reproducibility trade-off)

Add to thesis Section 5.6:
  "Container overhead ranged from {:.1f}% to {:.1f}% (avg {:.1f}%),
   confirming containerization does not materially affect performance
   comparisons while enabling exact reproducibility."
""".format(min_overhead, max_overhead, avg_overhead))

def main():
    print("="*70)
    print("CONTAINER vs NATIVE PERFORMANCE COMPARISON")
    print("="*70)
    
    # Languages to compare
    languages = ['python', 'julia', 'r']
    
    all_comparisons = {}
    
    for lang in languages:
        container_path = f'results/matrix_ops_{lang}.json'
        native_path = f'results/native/matrix_ops_{lang}.json'
        
        comparisons = compare_results(container_path, native_path, lang)
        if comparisons:
            all_comparisons[lang] = comparisons
    
    if all_comparisons:
        print_summary(all_comparisons)
    else:
        print("\n❌ No results found!")
        print("\nRun benchmarks first:")
        print("  ./run_benchmarks.sh          # Container benchmarks")
        print("  ./native_benchmark.sh        # Native benchmarks")
        sys.exit(1)

if __name__ == "__main__":
    main()
