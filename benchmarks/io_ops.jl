#!/usr/bin/env julia
"""
===============================================================================
I/O Operations Benchmark - Julia Implementation
===============================================================================
Benchmark tasks: CSV write/read, Binary write/read, Random access
Demonstrates Julia's I/O performance advantages
Following Chen & Revels (2016) methodology: minimum as primary estimator
===============================================================================
"""

using CSV
using DataFrames
using Random
using JSON3
using Statistics

function benchmark_csv_write(n_rows=1_000_000)
    """Write 1M rows to CSV file"""
    # Pre-generate data (not timed)
    df = DataFrame(
        id = 1:n_rows,
        value = randn(n_rows),
        category = rand(["A", "B", "C", "D"], n_rows),
        timestamp = rand(1:1000000, n_rows)
    )
    
    # Timed operation
    start_time = time()
    CSV.write("data/benchmark_output.csv", df)
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_csv_read()
    """Read 1M rows from CSV file"""
    start_time = time()
    df = CSV.read("data/benchmark_output.csv", DataFrame)
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_binary_write(n_elements=10_000_000)
    """Write 10M numbers to binary file"""
    # Pre-generate data (not timed)
    data = randn(n_elements)
    
    # Timed operation
    start_time = time()
    open("data/benchmark_binary.bin", "w") do io
        write(io, data)
    end
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_binary_read()
    """Read 10M numbers from binary file"""
    start_time = time()
    data = Vector{Float64}(undef, 10_000_000)
    open("data/benchmark_binary.bin", "r") do io
        read!(io, data)
    end
    elapsed = time() - start_time
    
    return elapsed
end

function benchmark_random_access(n_reads=10000)
    """Random access reads from file"""
    # Create test file if needed
    if !isfile("data/benchmark_binary.bin")
        data = randn(10_000_000)
        open("data/benchmark_binary.bin", "w") do io
            write(io, data)
        end
    end
    
    # Generate random positions (not timed)
    Random.seed!(42)
    positions = rand(1:9_999_999, n_reads) .* 8  # 8 bytes per Float64
    
    # Timed operation
    start_time = time()
    results = Vector{Float64}(undef, n_reads)
    open("data/benchmark_binary.bin", "r") do io
        for (i, pos) in enumerate(positions)
            seek(io, pos)
            results[i] = read(io, Float64)
        end
    end
    elapsed = time() - start_time
    
    return elapsed
end

function main()
    println("=" ^ 70)
    println("JULIA - I/O Operations Benchmark")
    println("Following Chen & Revels (2016) methodology")
    println("=" ^ 70)
    
    # Configuration
    n_rows = 1_000_000
    n_elements = 10_000_000
    n_random_reads = 10_000
    n_runs = 10
    
    results = Dict()
    
    # Task 1: CSV Write
    println("\n[1/5] CSV Write ($(n_rows) rows)...")
    times = [benchmark_csv_write(n_rows) for _ in 1:n_runs]
    results["csv_write"] = Dict(
        "min" => minimum(times),      # PRIMARY (Chen & Revels 2016)
        "mean" => mean(times),
        "median" => median(times),
        "std" => std(times),
        "max" => maximum(times),
        "all_times" => times
    )
    println("  ✓ Min:    $(round(results["csv_write"]["min"], digits=4))s (PRIMARY)")
    println("    Mean:   $(round(results["csv_write"]["mean"], digits=4))s ± $(round(results["csv_write"]["std"], digits=4))s")
    println("    Median: $(round(results["csv_write"]["median"], digits=4))s")
    
    # Task 2: CSV Read
    println("\n[2/5] CSV Read ($(n_rows) rows)...")
    times = [benchmark_csv_read() for _ in 1:n_runs]
    results["csv_read"] = Dict(
        "min" => minimum(times),
        "mean" => mean(times),
        "median" => median(times),
        "std" => std(times),
        "max" => maximum(times),
        "all_times" => times
    )
    println("  ✓ Min:    $(round(results["csv_read"]["min"], digits=4))s (PRIMARY)")
    println("    Mean:   $(round(results["csv_read"]["mean"], digits=4))s ± $(round(results["csv_read"]["std"], digits=4))s")
    
    # Task 3: Binary Write
    println("\n[3/5] Binary Write ($(n_elements) elements)...")
    times = [benchmark_binary_write(n_elements) for _ in 1:n_runs]
    results["binary_write"] = Dict(
        "min" => minimum(times),
        "mean" => mean(times),
        "median" => median(times),
        "std" => std(times),
        "max" => maximum(times),
        "all_times" => times
    )
    println("  ✓ Min:    $(round(results["binary_write"]["min"], digits=4))s (PRIMARY)")
    println("    Mean:   $(round(results["binary_write"]["mean"], digits=4))s ± $(round(results["binary_write"]["std"], digits=4))s")
    
    # Task 4: Binary Read
    println("\n[4/5] Binary Read ($(n_elements) elements)...")
    times = [benchmark_binary_read() for _ in 1:n_runs]
    results["binary_read"] = Dict(
        "min" => minimum(times),
        "mean" => mean(times),
        "median" => median(times),
        "std" => std(times),
        "max" => maximum(times),
        "all_times" => times
    )
    println("  ✓ Min:    $(round(results["binary_read"]["min"], digits=4))s (PRIMARY)")
    println("    Mean:   $(round(results["binary_read"]["mean"], digits=4))s ± $(round(results["binary_read"]["std"], digits=4))s")
    
    # Task 5: Random Access
    println("\n[5/5] Random Access ($(n_random_reads) reads)...")
    times = [benchmark_random_access(n_random_reads) for _ in 1:n_runs]
    results["random_access"] = Dict(
        "min" => minimum(times),
        "mean" => mean(times),
        "median" => median(times),
        "std" => std(times),
        "max" => maximum(times),
        "all_times" => times
    )
    println("  ✓ Min:    $(round(results["random_access"]["min"], digits=4))s (PRIMARY)")
    println("    Mean:   $(round(results["random_access"]["mean"], digits=4))s ± $(round(results["random_access"]["std"], digits=4))s")
    
    # Save results
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    output = Dict(
        "language" => "Julia",
        "julia_version" => string(VERSION),
        "csv_rows" => n_rows,
        "binary_elements" => n_elements,
        "random_reads" => n_random_reads,
        "n_runs" => n_runs,
        "methodology" => "Chen & Revels (2016): minimum as primary estimator",
        "results" => results
    )
    
    open("results/io_ops_julia.json", "w") do io
        JSON3.pretty(io, output)
    end
    
    println("✓ Results saved to: results/io_ops_julia.json")
    println("\nPrimary metrics (MINIMUM execution time):")
    println("  CSV write:      $(round(results["csv_write"]["min"], digits=4))s")
    println("  CSV read:       $(round(results["csv_read"]["min"], digits=4))s")
    println("  Binary write:   $(round(results["binary_write"]["min"], digits=4))s")
    println("  Binary read:    $(round(results["binary_read"]["min"], digits=4))s")
    println("  Random access:  $(round(results["random_access"]["min"], digits=4))s")
    
    # Cleanup
    rm("data/benchmark_output.csv", force=true)
    rm("data/benchmark_binary.bin", force=true)
end

main()
