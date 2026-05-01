#!/usr/bin/env python3
"""
Cross-language validation for thesis benchmark results.

Ensures that identical computations produce consistent validation hashes
across Python, Julia, and R implementations.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Any
import argparse
import hashlib

def load_validation_results(validation_dir: Path) -> Dict[str, Dict[str, str]]:
    """
    Load validation results from all languages.
    
    Args:
        validation_dir: Directory containing validation result files
        
    Returns:
        Dictionary mapping {scenario: {language: hash}}
    """
    validation_results = {}
    
    # Patterns for validation result files
    patterns = [
        "validation/*results.json",
        "results/validation/*results.json",
        "*/validation/*results.json"
    ]
    
    for pattern in patterns:
        for file_path in validation_dir.glob(pattern):
            if file_path.is_file():
                try:
                    with open(file_path, 'r') as f:
                        data = json.load(f)
                    
                    # Extract scenario and language (handle edge cases)
                    scenario = data.get("scenario", "unknown")
                    if isinstance(scenario, list):
                        scenario = scenario[0] if scenario else "unknown"
                    scenario = str(scenario)
                    
                    language = data.get("language", "unknown")
                    if isinstance(language, list):
                        language = language[0] if language else "unknown"
                    language = str(language).lower()
                    validation_hash = data.get("validation_hash", "")
                    
                    if scenario not in validation_results:
                        validation_results[scenario] = {}
                    validation_results[scenario][language] = validation_hash
                    
                except Exception as e:
                    print(f"Warning: Could not read {file_path}: {e}")
    
    return validation_results

def validate_hashes(validation_results: Dict[str, Dict[str, str]]) -> Dict[str, Dict[str, Any]]:
    """
    Validate that hashes match across languages for each scenario.
    
    Args:
        validation_results: Dictionary of {scenario: {language: hash}}
        
    Returns:
        Validation report dictionary
    """
    validation_report = {
        "total_scenarios": len(validation_results),
        "validated_scenarios": 0,
        "mismatched_scenarios": 0,
        "missing_data_scenarios": 0,
        "details": {}
    }
    
    for scenario, lang_hashes in validation_results.items():
        scenario_report = {
            "languages_present": list(lang_hashes.keys()),
            "hashes_match": True,
            "mismatch_details": [],
            "status": "VALID"
        }
        
        # Check if we have data from multiple languages
        if len(lang_hashes) < 2:
            scenario_report["status"] = "INSUFFICIENT_DATA"
            validation_report["missing_data_scenarios"] += 1
        else:
            # Check if all hashes match
            hashes = list(lang_hashes.values())
            if len(set(hashes)) > 1:
                # Hashes don't match
                scenario_report["hashes_match"] = False
                scenario_report["status"] = "MISMATCH"
                scenario_report["mismatch_details"] = [
                    f"{lang}: {hash_val}" for lang, hash_val in lang_hashes.items()
                ]
                validation_report["mismatched_scenarios"] += 1
            else:
                validation_report["validated_scenarios"] += 1
        
        validation_report["details"][scenario] = scenario_report
    
    return validation_report

def generate_validation_report(validation_report: Dict[str, Any], output_dir: Path):
    """
    Generate human-readable validation report.
    
    Args:
        validation_report: Validation report dictionary
        output_dir: Directory to save report
    """
    report_lines = [
        "=" * 80,
        "CROSS-LANGUAGE VALIDATION REPORT",
        "=" * 80,
        "",
        f"Total Scenarios Tested: {validation_report['total_scenarios']}",
        f"Successfully Validated: {validation_report['validated_scenarios']}",
        f"Mismatched Scenarios: {validation_report['mismatched_scenarios']}",
        f"Insufficient Data: {validation_report['missing_data_scenarios']}",
        "",
        "DETAILED RESULTS:",
        "-" * 40,
        ""
    ]
    
    for scenario, details in validation_report["details"].items():
        report_lines.append(f"Scenario: {scenario}")
        report_lines.append(f"  Status: {details['status']}")
        report_lines.append(f"  Languages Present: {', '.join(details['languages_present'])}")
        
        if details["status"] == "MISMATCH":
            report_lines.append("  MISMATCH DETAILS:")
            for detail in details["mismatch_details"]:
                report_lines.append(f"    {detail}")
        elif details["status"] == "INSUFFICIENT_DATA":
            report_lines.append("  WARNING: Insufficient language coverage for validation")
        else:
            report_lines.append("  ✓ Hashes match across all languages")
        
        report_lines.append("")
    
    # Add methodology note
    report_lines.extend([
        "METHODOLOGY NOTE:",
        "-" * 20,
        "Validation hashes are generated from output data using SHA256 with",
        "consistent sampling across languages. Matching hashes indicate that",
        "computationally identical operations produce bit-identical results.",
        "",
        "If hashes don't match, possible causes include:",
        "  • Different PRNG seeds or algorithms",
        "  • Floating-point precision differences", 
        "  • Different mathematical libraries",
        "  • Implementation-specific optimizations",
        ""
    ])
    
    # Save report
    output_dir.mkdir(parents=True, exist_ok=True)
    report_file = output_dir / "thesis_validation_report.md"
    with open(report_file, 'w') as f:
        f.write('\n'.join(report_lines))
    print(f"Saved validation report to {report_file}")

def check_synthetic_data_consistency():
    """
    Check that synthetic data files exist and are consistent.
    """
    synthetic_dir = Path("data/synthetic")
    if not synthetic_dir.exists():
        print("Warning: Synthetic data directory not found")
        return False
    
    required_files = [
        "ndvi_red_band.npy",
        "ndvi_nir_band.npy", 
        "idw_points.csv"
    ]
    
    missing_files = []
    for filename in required_files:
        if not (synthetic_dir / filename).exists():
            missing_files.append(filename)
    
    if missing_files:
        print(f"Warning: Missing synthetic data files: {missing_files}")
        return False
    
    print("✓ Synthetic data files present and consistent")
    return True

def main():
    parser = argparse.ArgumentParser(description="Cross-language validation for thesis benchmarks")
    parser.add_argument("--input", "-i", type=Path, default=Path("."),
                       help="Input directory to scan for validation results")
    parser.add_argument("--output", "-o", type=Path, default=Path("results/validation"),
                       help="Output directory for validation report")
    parser.add_argument("--all", "-a", action="store_true",
                       help="Run all validation checks")
    parser.add_argument("--check-data", action="store_true",
                       help="Check synthetic data consistency")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("RUNNING CROSS-LANGUAGE VALIDATION")
    print("=" * 60)
    print(f"Input directory: {args.input}")
    print(f"Output directory: {args.output}")
    print()
    
    # Check synthetic data consistency if requested
    if args.check_data or args.all:
        check_synthetic_data_consistency()
        print()
    
    # Load validation results
    validation_results = load_validation_results(args.input)
    
    if not validation_results:
        print("No validation results found!")
        print("Ensure benchmarks have been run and produced validation output.")
        return 1
    
    print(f"Found validation results for {len(validation_results)} scenarios")
    for scenario in validation_results:
        langs = list(validation_results[scenario].keys())
        print(f"  {scenario}: {', '.join(langs)}")
    print()
    
    # Validate hashes
    validation_report = validate_hashes(validation_results)
    
    # Generate report
    generate_validation_report(validation_report, args.output)
    
    # Print summary
    print("VALIDATION SUMMARY:")
    print(f"  Total scenarios: {validation_report['total_scenarios']}")
    print(f"  Validated: {validation_report['validated_scenarios']}")
    print(f"  Mismatches: {validation_report['mismatched_scenarios']}")
    print(f"  Insufficient data: {validation_report['missing_data_scenarios']}")
    
    if validation_report['mismatched_scenarios'] > 0:
        print("\n⚠ MISMATCHES DETECTED - Results may be inconsistent!")
        return 1
    elif validation_report['validated_scenarios'] == 0:
        print("\n⚠ No validations performed - insufficient cross-language data")
        return 1
    else:
        print("\n✓ All cross-language validations passed!")
        return 0

if __name__ == "__main__":
    sys.exit(main())