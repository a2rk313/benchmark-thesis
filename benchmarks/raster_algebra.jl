#!/usr/bin/env julia
"""
SCENARIO E: Raster Algebra & Band Math - Julia Implementation
Tests: Band arithmetic, NDVI calculation, spectral indices
"""

using MAT
using Statistics
using LinearAlgebra
using Random
using JSON3
using Images

const OUTPUT_DIR = "validation"
const RESULTS_DIR = "results"

include(joinpath(@__DIR__, "common_hash.jl"))

function load_cuprite_bands(data_mode="auto")
    if data_mode == "synthetic"
        Random.seed!(42)
        shape = (512, 614)
        return (
            green=rand(Float32, shape) .* 1000,
            red=rand(Float32, shape) .* 800,
            nir=rand(Float32, shape) .* 2000,
            swir=rand(Float32, shape) .* 1500,
            shape=(4, shape...)
        ), "synthetic"
    end
    try
        mat_path = joinpath(@__DIR__, "..", "data", "Cuprite.mat")
        if isfile(mat_path)
            mat_file = matopen(mat_path, "r")
            keys_list = keys(mat_file)
            data_key = first(keys_list)
            data = read(mat_file, data_key)
            close(mat_file)
            green = Float32.(data[:, :, 31])
            red = Float32.(data[:, :, 51])
            nir = Float32.(data[:, :, 71])
            swir = Float32.(data[:, :, 91])
            println("  ✓ Loaded real Cuprite data: $(size(data))")
            return (green=green, red=red, nir=nir, swir=swir, shape=size(data)), "real"
        elseif data_mode == "real"
            println("  x Cuprite.mat not found")
            exit(1)
        end
    catch e
        println("Warning: Could not load Cuprite data: $e")
        if data_mode == "real"
            println("  x Real data required but unavailable")
            exit(1)
        end
        println("  → Using synthetic data instead...")
    end
    Random.seed!(42)
    shape = (512, 614)
    return (
        green=rand(Float32, shape) .* 1000,
        red=rand(Float32, shape) .* 800,
        nir=rand(Float32, shape) .* 2000,
        swir=rand(Float32, shape) .* 1500,
        shape=(4, shape...)
    ), "synthetic"
end

function benchmark_ndvi(nir, red)
    numerator = nir .- red
    denominator = nir .+ red
    ndvi = @. numerator / denominator
    ndvi[denominator .== 0] .= 0
    return ndvi
end

function benchmark_band_arithmetic(green, red, nir, swir)
    sum_arr = green .+ red .+ nir .+ swir
    diff_arr = nir .- red
    ratio_arr = nir ./ max.(red, eps(Float32))
    blue_arr = green .* 0.8f0
    evi_arr = @. 2.5f0 * (nir - red) / (nir + 6.0f0*red - 7.5f0*blue_arr + 1.0f0)
    L_val = 0.5f0
    savi_arr = @. ((nir - red) / (nir + red + L_val)) * (1.0f0 + L_val)
    ndwi_arr = @. (green - nir) / (green + nir)
    nbr_arr = @. (nir - swir) / (nir + swir)
    return (sum=sum_arr, diff=diff_arr, ratio=ratio_arr, evi=evi_arr, savi=savi_arr, ndwi=ndwi_arr, nbr=nbr_arr)
end

function run_benchmark(func, runs=10, warmup=2)
    for _ in 1:warmup
        func()
    end
    
    times = Float64[]
    result = nothing
    for _ in 1:runs
        t_start = time_ns()
        result = func()
        t_end = time_ns()
        push!(times, (t_end - t_start) / 1e9)
    end
    
    return times, result
end

function run_raster_algebra_benchmark(data_mode="auto")
    println("=" ^ 70)
    println("JULIA - Scenario E: Raster Algebra & Band Math")
    println("=" ^ 70)

    println("\n[1/4] Loading hyperspectral data...")
    bands, data_source = load_cuprite_bands(data_mode)
    println("  ✓ Loaded $(bands.shape[1]) bands, shape: $(bands.shape[2])x$(bands.shape[3]) ($(bands.shape[2] * bands.shape[3]) pixels)")
    
    results = Dict()
    all_hashes = []
    
    println("\n[2/4] Testing NDVI calculation...")
    
    function ndvi_task()
        return benchmark_ndvi(bands.nir, bands.red)
    end
    
    GC.gc()
    times, ndvi_result = run_benchmark(ndvi_task, 10, 2)
    ndvi_hash = generate_hash(ndvi_result)
    push!(all_hashes, ndvi_hash)
    
    println("  ✓ Min: $(minimum(times))s (primary)")
    println("  ✓ Mean: $(mean(times))s ± $(std(times))s")
    println("  ✓ Hash: $ndvi_hash")
    
    results["ndvi"] = Dict(
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "median_time_s" => median(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "validation_hash" => ndvi_hash
    )
    
    println("\n[3/4] Testing band arithmetic...")
    
    function band_math_task()
        return benchmark_band_arithmetic(bands.green, bands.red, bands.nir, bands.swir)
    end
    
    GC.gc()
    times, indices_result = run_benchmark(band_math_task, 10, 2)
    indices_values = values(indices_result) |> collect
    indices_hash = generate_hash(indices_values)
    push!(all_hashes, indices_hash)
    
    println("  ✓ Min: $(minimum(times))s (primary)")
    println("  ✓ Mean: $(mean(times))s ± $(std(times))s")
    println("  ✓ Hash: $indices_hash")
    
    results["band_arithmetic"] = Dict(
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "median_time_s" => median(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "validation_hash" => indices_hash
    )
    
    println("\n[4/4] Testing 3x3 convolution...")

    function conv_task()
        nir = bands.nir
        kernel = ones(Float32, 3, 3) ./ 9.0f0
        imfilter(nir, kernel, Pad(:constant, 0.0f0))
    end
    
    GC.gc()
    times, conv_result = run_benchmark(conv_task, 10, 2)
    conv_hash = generate_hash(conv_result)
    push!(all_hashes, conv_hash)
    
    println("  ✓ Min: $(minimum(times))s (primary)")
    println("  ✓ Mean: $(mean(times))s ± $(std(times))s")
    println("  ✓ Hash: $conv_hash")
    
    results["convolution_3x3"] = Dict(
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "median_time_s" => median(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "validation_hash" => conv_hash
    )
    
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    mkpath(OUTPUT_DIR)
    mkpath(RESULTS_DIR)
    
    output_data = Dict(
        "language" => "julia",
        "scenario" => "raster_algebra",
        "data_source" => data_source,
        "data_description" => data_source == "real" ? "Cuprite.mat" : "synthetic 4×512×614",
        "data_shape" => [bands.shape...],
        "results" => results,
        "all_hashes" => all_hashes,
        "combined_hash" => generate_hash(all_hashes)
    )
    
    open("$OUTPUT_DIR/raster_algebra_julia_results.json", "w") do f
        JSON3.pretty(f, output_data)
    end
    
    println("✓ Results saved")
    println("✓ Combined validation hash: $(output_data["combined_hash"])")
    
    println("\n" * "=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)
    
    return output_data
end

# Parse CLI args
data_mode = "auto"
for (i, arg) in enumerate(ARGS)
    if arg == "--data" && i < length(ARGS)
        data_mode = ARGS[i+1]
    end
end
run_raster_algebra_benchmark(data_mode)
