#!/usr/bin/env python3
"""
Main Benchmark Runner
Runs all benchmarks across Python, Julia, and R languages.
"""
from pathlib import Path

import argparse
import os
import subprocess
import sys

# Dynamic path resolution
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"




# Important: Run from project root so "data/" paths work
BENCHMARK_DIR = Path(__file__).parent
PROJECT_DIR = BENCHMARK_DIR.parent

# Benchmark scenarios
SCENARIOS = {
    "matrix_ops": {
        "name": "Matrix Operations",
        "files": {
            "python": "benchmarks/matrix_ops.py", "python-jit": "benchmarks/matrix_ops.py",
            "julia": "benchmarks/matrix_ops.jl",
            "r": "benchmarks/matrix_ops.R",
        },
    },
    "io_ops": {
        "name": "I/O Operations",
        "files": {"python": "benchmarks/io_ops.py", "python-jit": "benchmarks/io_ops.py", "julia": "benchmarks/io_ops.jl", "r": "benchmarks/io_ops.R"},
    },
    "hsi_stream": {
        "name": "Hyperspectral SAM",
        "files": {
            "python": "benchmarks/hsi_stream.py", "python-jit": "benchmarks/hsi_stream.py",
            "julia": "benchmarks/hsi_stream.jl",
            "r": "benchmarks/hsi_stream.R",
        },
    },
    "vector_pip": {
        "name": "Vector Point-in-Polygon",
        "files": {
            "python": "benchmarks/vector_pip.py", "python-jit": "benchmarks/vector_pip.py",
            "julia": "benchmarks/vector_pip.jl",
            "r": "benchmarks/vector_pip.R",
        },
    },
    "interpolation": {
        "name": "IDW Interpolation",
        "files": {
            "python": "benchmarks/interpolation_idw.py", "python-jit": "benchmarks/interpolation_idw.py",
            "julia": "benchmarks/interpolation_idw.jl",
            "r": "benchmarks/interpolation_idw.R",
        },
    },
    "timeseries": {
        "name": "Time-Series NDVI",
        "files": {
            "python": "benchmarks/timeseries_ndvi.py", "python-jit": "benchmarks/timeseries_ndvi.py",
            "julia": "benchmarks/timeseries_ndvi.jl",
            "r": "benchmarks/timeseries_ndvi.R",
        },
    },
    "raster_algebra": {
        "name": "Raster Algebra & Band Math",
        "files": {
            "python": "benchmarks/raster_algebra.py", "python-jit": "benchmarks/raster_algebra.py",
            "julia": "benchmarks/raster_algebra.jl",
            "r": "benchmarks/raster_algebra.R",
        },
    },
    "zonal_stats": {
        "name": "Zonal Statistics",
        "files": {
            "python": "benchmarks/zonal_stats.py", "python-jit": "benchmarks/zonal_stats.py",
            "julia": "benchmarks/zonal_stats.jl",
            "r": "benchmarks/zonal_stats.R",
        },
    },
    "reprojection": {
        "name": "Coordinate Reprojection",
        "files": {
            "python": "benchmarks/reprojection.py", "python-jit": "benchmarks/reprojection.py",
            "julia": "benchmarks/reprojection.jl",
            "r": "benchmarks/reprojection.R",
        },
    },
}


def is_bootc():
    """Check if we are running in the benchmark-bootc environment."""
    return os.path.exists("/etc/benchmark-bootc-release")


def run_command(cmd, cwd=None, description=None, env=None):
    """Run a shell command and handle errors."""
    if description:
        print(f"\n{'=' * 60}")
        print(f"{description}")
        print("=" * 60)

    # Merge current environment with provided env
    current_env = os.environ.copy()
    if env:
        current_env.update(env)
    
    # ACADEMIC RIGOR: Force thread synchronization for all subprocesses
    current_env["JULIA_NUM_THREADS"] = "8"
    current_env["OPENBLAS_NUM_THREADS"] = "8"
    current_env["FLEXIBLAS_NUM_THREADS"] = "8"
    current_env["GOTO_NUM_THREADS"] = "8"
    current_env["OMP_NUM_THREADS"] = "8"
    current_env["FLEXIBLAS"] = "OPENBLAS-OPENMP"

    try:
        # Run from PROJECT_DIR by default so data/ is accessible
        result = subprocess.run(
            cmd, shell=True, cwd=cwd or PROJECT_DIR, capture_output=False, text=True,
            env=current_env
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Error running command: {e}")
        return False



def run_python_jit_benchmark(script):
    """Run a Python benchmark using the JIT-enabled interpreter."""
    env = {}
    if is_bootc():
        # Use custom JIT Python and bridge to system packages
        env["PYTHONPATH"] = f"/usr/lib64/python3.14/site-packages:/usr/lib/python3.14/site-packages:/usr/local/lib/python3.14/site-packages:/usr/local/lib64/python3.14/site-packages"
        cmd = f"python3-jit {script}"
    else:
        # Fallback to standard python3 if not in bootc (or assuming user has python3-jit)
        cmd = f"python3-jit {script}"
    
    return run_command(cmd, description=f"Python-JIT: {script}", env=env)


def run_python_benchmark(script):
    """Run a Python benchmark."""
    env = {}
    if is_bootc():
        # Use system Python and pre-baked packages
        env["PYTHONPATH"] = f"/usr/local/lib/python-deps:{os.environ.get('PYTHONPATH', '')}"
        cmd = f"python3 {script}"
    else:
        cmd = f"python3 {script}"
    
    return run_command(cmd, description=f"Python: {script}", env=env)


def run_julia_benchmark(script):
    """Run a Julia benchmark."""
    env = {}
    if is_bootc():
        # Use system Julia and pre-baked depot
        env["JULIA_DEPOT_PATH"] = "/usr/share/julia/depot"
        julia_cmd = "/usr/bin/julia"
    else:
        julia_cmd = "julia"
    
    cmd = f"{julia_cmd} {script}"
    return run_command(cmd, description=f"Julia: {script}", env=env)


def run_r_benchmark(script):
    """Run an R benchmark."""
    cmd = f"Rscript {script}"
    return run_command(cmd, description=f"R: {script}")


def run_scenario(scenario_name, languages=None):
    """Run a specific benchmark scenario."""
    if scenario_name not in SCENARIOS:
        print(f"Unknown scenario: {scenario_name}")
        return {}

    scenario = SCENARIOS[scenario_name]
    print(f"\n{'#' * 60}")
    print(f"# {scenario['name']}")
    print(f"{'#' * 60}")

    scenario_results = {}

    for lang, script in scenario["files"].items():
        if languages and lang not in languages:
            continue

        script_path = PROJECT_DIR / script
        if not script_path.exists():
            print(f"⚠ {script} not found, skipping...")
            continue

        if lang == "python":
            success = run_python_benchmark(script)
        elif lang == "python-jit":
            success = run_python_jit_benchmark(script)
        elif lang == "julia":
            success = run_julia_benchmark(script)
        elif lang == "r":
            success = run_r_benchmark(script)
        else:
            continue

        scenario_results[lang] = success
        if not success:
            print(f"✗ {lang.capitalize()} benchmark failed")

    return scenario_results


def run_all(languages=None):
    """Run all benchmarks."""
    print("\n" + "=" * 60)
    print("RUNNING ALL BENCHMARKS")
    print("=" * 60)

    all_results = {}

    for scenario_name in SCENARIOS:
        all_results[scenario_name] = run_scenario(scenario_name, languages)

    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    total_scenarios = len(SCENARIOS)
    scenarios_passed = 0

    for scenario_id, scenario in SCENARIOS.items():
        results = all_results.get(scenario_id, {})
        if not results:
            continue
            
        langs_status = []
        scenario_success = True
        for lang, success in results.items():
            status = "✓" if success else "✗"
            langs_status.append(f"{lang}: {status}")
            if not success:
                scenario_success = False
        
        if scenario_success:
            scenarios_passed += 1
            
        status_icon = "✓" if scenario_success else "✗"
        print(f"  {status_icon} {scenario['name']:<30} [ {', '.join(langs_status)} ]")

    print(f"\nScenarios Passed: {scenarios_passed}/{total_scenarios}")

    return scenarios_passed == total_scenarios


def main():
    parser = argparse.ArgumentParser(description="Thesis Benchmark Runner")
    parser.add_argument("--scenario", "-s", help="Run specific scenario")
    parser.add_argument(
        "--lang",
        "-l",
        nargs="+",
        choices=["python", "python-jit", "julia", "r"],
        help="Run specific languages",
    )
    parser.add_argument("--all", "-a", action="store_true", help="Run all benchmarks")

    args = parser.parse_args()

    if args.scenario:
        run_scenario(args.scenario, args.lang)
    else:
        run_all(args.lang)


if __name__ == "__main__":
    main()