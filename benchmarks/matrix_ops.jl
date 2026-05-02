#!/usr/bin/env julia
"""
===============================================================================
Matrix Operations Benchmark - Julia Implementation
===============================================================================
Reproduces Tedesco et al. (2025) matrix operation benchmarks
Tasks: Creation/Transpose/Reshape, Power, Sorting, Cross-product, Determinant
===============================================================================
"""

using LinearAlgebra
using Statistics
using JSON3
using Printf
using Random

function make_rng(data_mode)
    return Random.default_rng(42)
end

function benchmark_matrix_creation_transpose_reshape(n=2500, rng=Random.default_rng())
    """
    Task 1.1: Matrix Creation + Transpose + Reshape
    """
    start_time = time()
    A = randn(rng, n, n)
    A = transpose(A)
    new_rows = Int(n * 2 / 5)
    new_cols = Int(n * n / new_rows)
    A = reshape(A, new_rows, new_cols)
    A = transpose(A)
    elapsed = time() - start_time
    return elapsed
end

function benchmark_matrix_power(n=2500, rng=Random.default_rng())
    """
    Task 1.2: Element-wise Matrix Exponentiation
    """
    A = randn(rng, n, n)
    A = abs.(A) ./ 2.0
    start_time = time()
    A_pow = A .^ 10
    elapsed = time() - start_time
    return elapsed
end

function benchmark_sorting(n=1_000_000, rng=Random.default_rng())
    """
    Task 1.3: Sorting Random Values
    """
    arr = randn(rng, n)
    start_time = time()
    sort!(copy(arr))
    elapsed = time() - start_time
    return elapsed
end

function benchmark_crossproduct(n=2500, rng=Random.default_rng())
    """
    Task 1.4: Matrix Cross-Product (A'A)
    """
    A = randn(rng, n, n)
    start_time = time()
    B = A' * A
    elapsed = time() - start_time
    return elapsed
end

function benchmark_determinant(n=2500, rng=Random.default_rng())
    """
    Task 1.5: Matrix Determinant
    """
    A = randn(rng, n, n)
    start_time = time()
    det_val = det(A)
    elapsed = time() - start_time
    return elapsed
end

function format_number(n::Int)
    """Helper function for number formatting"""
    str = string(n)
    return replace(str, r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => ",")
end

function main()
    data_mode = "auto"
    size_mode = "small"
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--data" && i < length(ARGS)
            data_mode = ARGS[i+1]
            i += 2
        elseif ARGS[i] == "--size" && i < length(ARGS)
            size_mode = ARGS[i+1]
            i += 2
        else
            i += 1
        end
    end

    data_source = "synthetic"
    data_description = "random normal matrices (seed 42)"

    println("=" ^ 70)
    println("JULIA - Matrix Operations Benchmark")
    println("=" ^ 70)

    size_map = Dict("small" => 2500, "large" => 5000)
    n_matrix = size_map[size_mode]
    n_sort = 1_000_000
    n_runs = 30
    n_warmup = 5

    rng = make_rng(data_mode)
    
    results = Dict()
    
    # Warmup phase (Chen & Revels 2016: exclude startup/JIT overhead)
    println("\n  Warming up ($n_warmup runs + JIT compilation)...")
    for _ in 1:n_warmup
        benchmark_matrix_creation_transpose_reshape(n_matrix, rng)
    end
    println("  ✓ Warmup complete")

    # Task 1: Creation/Transpose/Reshape
    println("\n[1/5] Matrix Creation + Transpose + Reshape ($n_matrix×$n_matrix)...")
    GC.gc()
    times = [benchmark_matrix_creation_transpose_reshape(n_matrix, rng) for _ in 1:n_runs]
    results["matrix_creation"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["matrix_creation"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["matrix_creation"]["mean"], results["matrix_creation"]["std"])
    
    # Task 2: Matrix Power
    println("\n[2/5] Matrix Exponentiation ^10 ($n_matrix×$n_matrix)...")
    for _ in 1:n_warmup
        benchmark_matrix_power(n_matrix, rng)
    end
    GC.gc()
    times = [benchmark_matrix_power(n_matrix, rng) for _ in 1:n_runs]
    results["matrix_power"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["matrix_power"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["matrix_power"]["mean"], results["matrix_power"]["std"])
    
    # Task 3: Sorting
    println("\n[3/5] Sorting $(format_number(n_sort)) Random Values...")
    for _ in 1:n_warmup
        benchmark_sorting(n_sort, rng)
    end
    GC.gc()
    times = [benchmark_sorting(n_sort, rng) for _ in 1:n_runs]
    results["sorting"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["sorting"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["sorting"]["mean"], results["sorting"]["std"])
    
    # Task 4: Cross-product
    println("\n[4/5] Cross-Product A'A ($n_matrix×$n_matrix)...")
    for _ in 1:n_warmup
        benchmark_crossproduct(n_matrix, rng)
    end
    GC.gc()
    times = [benchmark_crossproduct(n_matrix, rng) for _ in 1:n_runs]
    results["crossproduct"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["crossproduct"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["crossproduct"]["mean"], results["crossproduct"]["std"])
    
    # Task 5: Determinant
    println("\n[5/5] Matrix Determinant ($n_matrix×$n_matrix)...")
    for _ in 1:n_warmup
        benchmark_determinant(n_matrix, rng)
    end
    GC.gc()
    times = [benchmark_determinant(n_matrix, rng) for _ in 1:n_runs]
    results["determinant"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["determinant"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["determinant"]["mean"], results["determinant"]["std"])
    
    # Save results with enhanced statistics
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    output = Dict(
        "language" => "Julia",
        "julia_version" => string(VERSION),
        "julia_num_threads" => string(Threads.nthreads()),
        "matrix_size" => n_matrix,
        "sorting_size" => n_sort,
        "n_runs" => n_runs,
        "n_warmup" => n_warmup,
        "data_source" => data_source,
        "data_description" => data_description,
        "methodology" => "Minimum time as primary estimator (Chen & Revels 2016)",
        "enhanced_stats" => true,
        "results" => results
    )
    
    mkpath("results")
    mkpath("validation")
    open("results/matrix_ops_julia.json", "w") do f
        JSON3.pretty(f, output)
    end
    
    # Save individual times for Python statistical analysis
    times_output = Dict(
        "benchmark" => "matrix_ops",
        "language" => "julia",
        "julia_version" => string(VERSION),
        "runs" => [
            Dict(
                "name" => "matrix_creation",
                "times" => results["matrix_creation"]["times"],
                "min_time" => results["matrix_creation"]["min"],
                "mean_time" => results["matrix_creation"]["mean"],
                "std_time" => results["matrix_creation"]["std"],
                "cv" => results["matrix_creation"]["std"] / results["matrix_creation"]["mean"],
                "median" => median(results["matrix_creation"]["times"])
            ),
            Dict(
                "name" => "matrix_power",
                "times" => results["matrix_power"]["times"],
                "min_time" => results["matrix_power"]["min"],
                "mean_time" => results["matrix_power"]["mean"],
                "std_time" => results["matrix_power"]["std"],
                "cv" => results["matrix_power"]["std"] / results["matrix_power"]["mean"],
                "median" => median(results["matrix_power"]["times"])
            ),
            Dict(
                "name" => "sorting",
                "times" => results["sorting"]["times"],
                "min_time" => results["sorting"]["min"],
                "mean_time" => results["sorting"]["mean"],
                "std_time" => results["sorting"]["std"],
                "cv" => results["sorting"]["std"] / results["sorting"]["mean"],
                "median" => median(results["sorting"]["times"])
            ),
            Dict(
                "name" => "crossproduct",
                "times" => results["crossproduct"]["times"],
                "min_time" => results["crossproduct"]["min"],
                "mean_time" => results["crossproduct"]["mean"],
                "std_time" => results["crossproduct"]["std"],
                "cv" => results["crossproduct"]["std"] / results["crossproduct"]["mean"],
                "median" => median(results["crossproduct"]["times"])
            ),
            Dict(
                "name" => "determinant",
                "times" => results["determinant"]["times"],
                "min_time" => results["determinant"]["min"],
                "mean_time" => results["determinant"]["mean"],
                "std_time" => results["determinant"]["std"],
                "cv" => results["determinant"]["std"] / results["determinant"]["mean"],
                "median" => median(results["determinant"]["times"])
            )
        ]
    )
    
    open("validation/matrix_ops_julia_times.json", "w") do f
        JSON3.pretty(f, times_output)
    end
    
    println("✓ Results saved to: results/matrix_ops_julia.json")
    println("✓ Times saved to: validation/matrix_ops_julia_times.json")
    println("\nNote: Minimum times are primary metrics (Chen & Revels 2016)")
    println("      Mean/median provided for context only")
end

main()
