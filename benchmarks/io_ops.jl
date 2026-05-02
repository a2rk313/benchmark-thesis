#!/usr/bin/env julia
"""
===============================================================================
I/O Operations Benchmark - Julia Implementation
===============================================================================
Tests file I/O performance for CSV and binary formats
Tasks: CSV Write/Read, Binary Write/Read
===============================================================================
"""

using CSV
using DataFrames
using Statistics
using JSON3
using Printf
using Random

function benchmark_csv_write(n_rows=1_000_000, rng=Random.default_rng())
    df = DataFrame(
        lat = rand(rng, Float64, n_rows) .* 180 .- 90,
        lon = rand(rng, Float64, n_rows) .* 360 .- 180,
        device_id = rand(rng, 1:10000, n_rows)
    )
    
    output_path = joinpath(@__DIR__, "..", "data", "io_test_julia.csv")
    
    start_time = time()
    CSV.write(output_path, df)
    elapsed = time() - start_time
    
    file_size = stat(output_path).size
    
    return elapsed, file_size
end

function benchmark_csv_read()
    input_path = joinpath(@__DIR__, "..", "data", "io_test_julia.csv")
    
    start_time = time()
    df = CSV.read(input_path, DataFrame)
    elapsed = time() - start_time
    
    return elapsed, nrow(df)
end

function benchmark_binary_write(n_values=1_000_000, rng=Random.default_rng())
    arr = randn(rng, Float64, n_values)
    
    output_path = joinpath(@__DIR__, "..", "data", "io_test_julia.bin")
    
    start_time = time()
    open(output_path, "w") do io
        write(io, arr)
    end
    elapsed = time() - start_time
    
    file_size = stat(output_path).size
    
    return elapsed, file_size
end

function benchmark_binary_read()
    input_path = joinpath(@__DIR__, "..", "data", "io_test_julia.bin")
    
    start_time = time()
    arr = open(input_path, "r") do io
        bytes = read(io)
        reinterpret(Float64, bytes)
    end
    elapsed = time() - start_time
    
    return elapsed, length(arr)
end

function format_number(n::Int)
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
    data_description = "random CSV/binary data (seed 42)"

    size_map = Dict("small" => 1_000_000, "large" => 10_000_000)
    n_csv_rows = size_map[size_mode]
    n_binary_values = size_map[size_mode]
    n_runs = 30
    n_warmup = 5

    rng = Random.default_rng(42)
    
    rng = Random.default_rng(42)

    println("=" ^ 70)
    println("JULIA - I/O Operations Benchmark ($size_mode size)")
    println("=" ^ 70)

    mkpath("data")

    results = Dict()

    for _ in 1:n_warmup
        benchmark_csv_write(n_csv_rows, rng)
    end

    # Task 1: CSV Write
    println("\n[1/4] CSV Write ($(format_number(n_csv_rows)) rows)...")
    times = Float64[]
    file_size = 0
    for _ in 1:n_runs
        GC.gc()
        t, size = benchmark_csv_write(n_csv_rows, rng)
        push!(times, t)
        file_size = size
    end
    results["csv_write"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "file_size_mb" => file_size / (1024^2),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["csv_write"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["csv_write"]["mean"], results["csv_write"]["std"])
    @printf("  ✓ File size: %.2f MB\n", results["csv_write"]["file_size_mb"])
    
    # Task 2: CSV Read
    println("\n[2/4] CSV Read ($(format_number(n_csv_rows)) rows)...")
    times = Float64[]
    n_rows = 0
    for _ in 1:n_runs
        GC.gc()
        t, rows = benchmark_csv_read()
        push!(times, t)
        n_rows = rows
    end
    results["csv_read"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "rows_read" => n_rows,
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["csv_read"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["csv_read"]["mean"], results["csv_read"]["std"])
    
    # Task 3: Binary Write
    println("\n[3/4] Binary Write ($(format_number(n_binary_values)) float64 values)...")
    times = Float64[]
    file_size = 0
    for _ in 1:n_runs
        GC.gc()
        t, size = benchmark_binary_write(n_binary_values, rng)
        push!(times, t)
        file_size = size
    end
    results["binary_write"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "file_size_mb" => file_size / (1024^2),
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["binary_write"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["binary_write"]["mean"], results["binary_write"]["std"])
    @printf("  ✓ File size: %.2f MB\n", results["binary_write"]["file_size_mb"])
    
    # Task 4: Binary Read
    println("\n[4/4] Binary Read ($(format_number(n_binary_values)) float64 values)...")
    times = Float64[]
    n_values = 0
    for _ in 1:n_runs
        GC.gc()
        t, values = benchmark_binary_read()
        push!(times, t)
        n_values = values
    end
    results["binary_read"] = Dict(
        "mean" => mean(times),
        "std" => std(times),
        "min" => minimum(times),
        "max" => maximum(times),
        "median" => median(times),
        "values_read" => n_values,
        "times" => times
    )
    @printf("  ✓ Min: %.4fs (primary)\n", results["binary_read"]["min"])
    @printf("  ✓ Mean: %.4fs ± %.4fs\n", results["binary_read"]["mean"], results["binary_read"]["std"])
    
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    output = Dict(
        "language" => "Julia",
        "julia_version" => string(VERSION),
        "csv_version" => string(pkgversion(CSV)),
        "n_csv_rows" => n_csv_rows,
        "n_binary_values" => n_binary_values,
        "n_runs" => n_runs,
        "data_source" => data_source,
        "data_description" => data_description,
        "methodology" => "Minimum time as primary estimator (Chen & Revels 2016)",
        "results" => results
    )
    
    mkpath("results")
    open("results/io_ops_julia.json", "w") do f
        JSON3.pretty(f, output)
    end
    
    println("✓ Results saved to: results/io_ops_julia.json")
    
    println("\nCleaning up test files...")
    for path in [joinpath(@__DIR__, "..", "data", "io_test_julia.csv"), joinpath(@__DIR__, "..", "data", "io_test_julia.bin")]
        if isfile(path)
            rm(path)
        end
    end
    println("✓ Cleanup complete")
    
    println("\nNote: Minimum times are primary metrics (Chen & Revels 2016)")
end

main()
