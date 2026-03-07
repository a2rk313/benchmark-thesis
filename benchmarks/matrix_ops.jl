#!/usr/bin/env julia
"""
===============================================================================
Matrix Operations Benchmark - Julia Implementation
===============================================================================
"""

using LinearAlgebra
using Statistics
using JSON
using Printf

function benchmark_matrix_creation_transpose_reshape(n=2500)
    start_time = time()
    A = randn(n, n)
    A = transpose(A)
    new_rows = Int(n * 3 / 5)
    new_cols = Int(n * 5 / 3)
    A = reshape(A, new_rows, new_cols)
    A = transpose(A)
    elapsed = time() - start_time
    return elapsed
end

function benchmark_matrix_power(n=2500)
    A = randn(n, n)
    A = abs.(A) ./ 2.0
    start_time = time()
    A_pow = A .^ 10
    elapsed = time() - start_time
    return elapsed
end

function benchmark_sorting(n=1_000_000)
    arr = randn(n)
    start_time = time()
    sort!(copy(arr))
    elapsed = time() - start_time
    return elapsed
end

function benchmark_crossproduct(n=2500)
    A = randn(n, n)
    start_time = time()
    B = A' * A
    elapsed = time() - start_time
    return elapsed
end

function benchmark_determinant(n=2500)
    A = randn(n, n)
    start_time = time()
    det_val = det(A)
    elapsed = time() - start_time
    return elapsed
end

function main()
    println("=" ^ 70)
    println("JULIA - Matrix Operations Benchmark")
    println("=" ^ 70)
    
    n_matrix = 2500
    n_sort = 1_000_000
    n_runs = 10
    
    results = Dict()
    
    println("\n[1/5] Matrix Creation + Transpose + Reshape ($n_matrix×$n_matrix)...")
    times = [benchmark_matrix_creation_transpose_reshape(n_matrix) for _ in 1:n_runs]
    results["matrix_creation"] = Dict("mean" => mean(times), "std" => std(times), "min" => minimum(times), "max" => maximum(times))
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["matrix_creation"]["mean"], results["matrix_creation"]["std"])
    
    println("\n[2/5] Matrix Exponentiation ^10 ($n_matrix×$n_matrix)...")
    times = [benchmark_matrix_power(n_matrix) for _ in 1:n_runs]
    results["matrix_power"] = Dict("mean" => mean(times), "std" => std(times), "min" => minimum(times), "max" => maximum(times))
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["matrix_power"]["mean"], results["matrix_power"]["std"])
    
    println("\n[3/5] Sorting $(format(n_sort)) Random Values...")
    times = [benchmark_sorting(n_sort) for _ in 1:n_runs]
    results["sorting"] = Dict("mean" => mean(times), "std" => std(times), "min" => minimum(times), "max" => maximum(times))
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["sorting"]["mean"], results["sorting"]["std"])
    
    println("\n[4/5] Cross-Product A'A ($n_matrix×$n_matrix)...")
    times = [benchmark_crossproduct(n_matrix) for _ in 1:n_runs]
    results["crossproduct"] = Dict("mean" => mean(times), "std" => std(times), "min" => minimum(times), "max" => maximum(times))
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["crossproduct"]["mean"], results["crossproduct"]["std"])
    
    println("\n[5/5] Matrix Determinant ($n_matrix×$n_matrix)...")
    times = [benchmark_determinant(n_matrix) for _ in 1:n_runs]
    results["determinant"] = Dict("mean" => mean(times), "std" => std(times), "min" => minimum(times), "max" => maximum(times))
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["determinant"]["mean"], results["determinant"]["std"])
    
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    output = Dict(
        "language" => "Julia",
        "julia_version" => string(VERSION),
        "matrix_size" => n_matrix,
        "sorting_size" => n_sort,
        "n_runs" => n_runs,
        "results" => results
    )
    
    open("results/matrix_ops_julia.json", "w") do f
        JSON.print(f, output, 2)
    end
    
    println("✓ Results saved to: results/matrix_ops_julia.json")
end

format(n) = replace(string(n), r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => ",")

main()
