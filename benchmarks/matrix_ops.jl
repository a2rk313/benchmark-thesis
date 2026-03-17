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
using JSON
using Printf

function benchmark_matrix_creation_transpose_reshape(n=2500)
    """
    Task 1.1: Matrix Creation + Transpose + Reshape
    """
    start_time = time()
    
    # Create
    A = randn(n, n)
    
    # Transpose
    A = transpose(A)
    
    # Reshape
    new_rows = Int(n * 3 / 5)
    new_cols = Int(n * 5 / 3)
    A = reshape(A, new_rows, new_cols)
    
    # Transpose again
    A = transpose(A)
    
    elapsed = time() - start_time
    return elapsed
end

function benchmark_matrix_power(n=2500)
    """
    Task 1.2: Element-wise Matrix Exponentiation
    """
    # Pre-generate data (not timed)
    A = randn(n, n)
    A = abs.(A) ./ 2.0
    
    # Timed operation
    start_time = time()
    A_pow = A .^ 10
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_sorting(n=1_000_000)
    """
    Task 1.3: Sorting Random Values
    """
    # Pre-generate data (not timed)
    arr = randn(n)
    
    # Timed operation
    start_time = time()
    sort!(copy(arr))
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_crossproduct(n=2500)
    """
    Task 1.4: Matrix Cross-Product (A'A)
    """
    # Pre-generate data (not timed)
    A = randn(n, n)
    
    # Timed operation
    start_time = time()
    B = A' * A
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_determinant(n=2500)
    """
    Task 1.5: Matrix Determinant
    """
    # Pre-generate data (not timed)
    A = randn(n, n)
    
    # Timed operation
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
    println("=" ^ 70)
    println("JULIA - Matrix Operations Benchmark")
    println("=" ^ 70)
    
    # Configuration
    n_matrix = 2500  # Matrix size
    n_sort = 1_000_000  # Sorting size
    n_runs = 10  # Number of runs
    
    results = Dict()
    
    # Task 1: Creation/Transpose/Reshape
    println("\n[1/5] Matrix Creation + Transpose + Reshape ($n_matrix×$n_matrix)...")
    times = [benchmark_matrix_creation_transpose_reshape(n_matrix) for _ in 1:n_runs]
    results["matrix_creation"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times)
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["matrix_creation"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["matrix_creation"]["mean"], results["matrix_creation"]["std"])
    
    # Task 2: Matrix Power
    println("\n[2/5] Matrix Exponentiation ^10 ($n_matrix×$n_matrix)...")
    times = [benchmark_matrix_power(n_matrix) for _ in 1:n_runs]
    results["matrix_power"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times)
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["matrix_power"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["matrix_power"]["mean"], results["matrix_power"]["std"])
    
    # Task 3: Sorting
    println("\n[3/5] Sorting $(format_number(n_sort)) Random Values...")
    times = [benchmark_sorting(n_sort) for _ in 1:n_runs]
    results["sorting"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times)
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["sorting"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["sorting"]["mean"], results["sorting"]["std"])
    
    # Task 4: Cross-product
    println("\n[4/5] Cross-Product A'A ($n_matrix×$n_matrix)...")
    times = [benchmark_crossproduct(n_matrix) for _ in 1:n_runs]
    results["crossproduct"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times)
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["crossproduct"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["crossproduct"]["mean"], results["crossproduct"]["std"])
    
    # Task 5: Determinant
    println("\n[5/5] Matrix Determinant ($n_matrix×$n_matrix)...")
    times = [benchmark_determinant(n_matrix) for _ in 1:n_runs]
    results["determinant"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times)
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["determinant"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["determinant"]["mean"], results["determinant"]["std"])
    
    # Save results
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    output = Dict(
        "language" => "Julia",
        "julia_version" => string(VERSION),
        "matrix_size" => n_matrix,
        "sorting_size" => n_sort,
        "n_runs" => n_runs,
        "methodology" => "Minimum time as primary estimator (Chen & Revels 2016)",
        "results" => results
    )
    
    mkpath("results")
    open("results/matrix_ops_julia.json", "w") do f
        JSON.print(f, output, 2)
    end
    
    println("✓ Results saved to: results/matrix_ops_julia.json")
    println("\nNote: Minimum times are primary metrics (Chen & Revels 2016)")
    println("      Mean/median provided for context only")
end

main()
