#!/usr/bin/env julia
"""
===============================================================================
SCENARIO D: Time-Series NDVI Analysis - Julia Implementation
===============================================================================
Task: Calculate NDVI statistics across 12-month time series
Dataset: Synthetic Landsat-like data (500x500 pixels × 12 dates × 2 bands)
Metrics: Temporal aggregation, SIMD vectorization, array operations
Methodology: Chen & Revels (2016) - min time as primary estimator
===============================================================================
"""

using Statistics
using Random
using LinearAlgebra
using JSON3
using SHA

include(joinpath(@__DIR__, "common_hash.jl"))

const RUNS = 10
const WARMUP = 2

function load_real_modis_ndvi()
    modis_dir = joinpath(@__DIR__, "..", "data", "modis")
    bin_path = joinpath(modis_dir, "modis_ndvi_timeseries.bin")
    hdr_path = joinpath(modis_dir, "modis_ndvi_timeseries.hdr")
    if isfile(bin_path) && isfile(hdr_path)
        try
            n_rows = n_cols = n_bands = 0
            for line in eachline(hdr_path)
                if startswith(line, "samples")
                    n_cols = parse(Int, strip(split(line, "=")[2]))
                elseif startswith(line, "lines")
                    n_rows = parse(Int, strip(split(line, "=")[2]))
                elseif startswith(line, "bands")
                    n_bands = parse(Int, strip(split(line, "=")[2]))
                end
            end
            data = reinterpret(Float32, read(bin_path))
            data = reshape(data, n_cols, n_rows, n_bands)
            data = permutedims(data, (3, 2, 1))
            println("  ✓ Loaded real MODIS NDVI: $n_bands × $n_rows × $n_cols")
            return Float32.(data)
        catch e
            println("  ⚠ Failed to load real MODIS data: $e")
        end
    end
    return nothing
end

function generate_synthetic_ndvi_stack(n_dates=46, height=1200, width=1200)
    Random.seed!(42)
    x = collect(LinRange(-1.0, 1.0, width))
    y = collect(LinRange(-1.0, 1.0, height))
    xx = repeat(x', height, 1)
    yy = repeat(y, 1, width)
    base_vegetation = Float32.(0.5 .* (1.0 .- (xx.^2 .+ yy.^2)))
    ndvi_stack = zeros(Float32, n_dates, height, width)
    for t in 1:n_dates
        vegetation_level = Float32(0.5 + 0.3 * sin(2π * (t-1) / n_dates))
        noise = randn(Float32, height, width) .* Float32(0.05)
        red = Float32.(0.1 .+ 0.2 .* (1.0 .- base_vegetation .* vegetation_level) .+ noise)
        nir = Float32.(0.3 .+ 0.5 .* base_vegetation .* vegetation_level .+ noise)
        epsilon = Float32(1e-6)
        ndvi = (nir .- red) ./ (nir .+ red .+ epsilon)
        ndvi_stack[t, :, :] = clamp.(ndvi, Float32(-0.1), Float32(1.0))
    end
    ndvi_stack
end

function load_ndvi_data(data_mode)
    if data_mode == "synthetic"
        return generate_synthetic_ndvi_stack(), "synthetic"
    end
    data = load_real_modis_ndvi()
    if data !== nothing
        return data, "real"
    end
    if data_mode == "real"
        println("  x Real MODIS data not available")
        exit(1)
    end
    println("  → Using synthetic NDVI stack")
    return generate_synthetic_ndvi_stack(), "synthetic"
end

function calculate_ndvi_statistics(ndvi_stack)
    n_dates, height, width = size(ndvi_stack)
    
    mean_ndvi = mean(ndvi_stack, dims=1)[1, :, :]
    max_ndvi = maximum(ndvi_stack, dims=1)[1, :, :]
    min_ndvi = minimum(ndvi_stack, dims=1)[1, :, :]
    
    time_index = Float32.(0:n_dates-1)
    mean_time = mean(time_index)
    denominator = sum((time_index .- mean_time).^2)
    
    ndvi_trend = zeros(Float32, height, width)
    for i in 1:height, j in 1:width
        pixel_series = ndvi_stack[:, i, j]
        numerator = sum((time_index .- mean_time) .* (pixel_series .- mean_ndvi[i, j]))
        ndvi_trend[i, j] = numerator / denominator
    end
    
    growing_season = sum(ndvi_stack .> Float32(0.3), dims=1)[1, :, :]
    amplitude = max_ndvi .- min_ndvi
    
    (mean_ndvi=mean_ndvi, ndvi_trend=ndvi_trend, amplitude=amplitude, growing_season=growing_season)
end

function main()
    data_mode = "auto"
    for (i, arg) in enumerate(ARGS)
        if arg == "--data" && i < length(ARGS)
            data_mode = ARGS[i+1]
        end
    end

    println("=" ^ 70)
    println("JULIA - Scenario D: Time-Series NDVI Analysis")
    println("=" ^ 70)

    println("\n[1/4] Loading NDVI stack...")
    ndvi_stack, data_source = load_ndvi_data(data_mode)
    n_dates, height, width = size(ndvi_stack)
    println("  ✓ Stack shape: $n_dates dates × $height × $width pixels")
    
    println("\n[2/4] Running NDVI time-series analysis ($RUNS runs, $WARMUP warmup)...")
    
    task = () -> calculate_ndvi_statistics(ndvi_stack)
    
    for _ in 1:WARMUP
        task()
    end
    
    GC.gc()
    times = Float64[]
    result = nothing
    for _ in 1:RUNS
        t_start = time_ns()
        result = task()
        t_end = time_ns()
        push!(times, (t_end - t_start) / 1e9)
    end
    
    println("  ✓ Min: $(minimum(times))s (primary)")
    println("  ✓ Mean: $(mean(times))s ± $(std(times))s")
    
    println("\n[3/4] Computing domain statistics...")
    mean_ndvi_val = mean(result.mean_ndvi)
    trend_val = mean(result.ndvi_trend)
    amplitude_val = mean(result.amplitude)
    growing_days = mean(result.growing_season)
    println("  ✓ Mean NDVI: $(round(mean_ndvi_val, digits=4))")
    println("  ✓ Mean trend: $(round(trend_val, digits=6))")
    println("  ✓ Mean amplitude: $(round(amplitude_val, digits=4))")
    println("  ✓ Avg growing season: $(round(growing_days, digits=1)) dates")
    
    println("\n[4/4] Validation and export...")
    hash_arrays = [vec(result.mean_ndvi), vec(result.ndvi_trend), vec(result.amplitude)]
    result_hash = generate_hash(hash_arrays)
    println("  ✓ Validation hash: $result_hash")
    
    results = Dict(
        "language" => "julia",
        "scenario" => "timeseries_ndvi",
        "data_source" => data_source,
        "data_description" => data_source == "real" ? "MODIS HDF" : "synthetic $n_dates×$height×$width",
        "n_dates" => n_dates,
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "mean_ndvi" => mean_ndvi_val,
        "mean_trend" => trend_val,
        "mean_amplitude" => amplitude_val,
        "avg_growing_season" => growing_days,
        "validation_hash" => result_hash
    )
    
    OUTPUT_DIR = joinpath(@__DIR__, "..", "results")
    VALIDATION_DIR = joinpath(@__DIR__, "..", "validation")
    mkpath(OUTPUT_DIR)
    mkpath(VALIDATION_DIR)
    
    open(joinpath(OUTPUT_DIR, "timeseries_ndvi_julia.json"), "w") do f
        JSON3.pretty(f, results)
    end
    open(joinpath(VALIDATION_DIR, "timeseries_julia_results.json"), "w") do f
        JSON3.pretty(f, results)
    end
    
    println("✓ Results saved")
    println("=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)
    
    return 0
end

exit(main())
