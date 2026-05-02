#!/usr/bin/env julia
"""
===============================================================================
SCENARIO A.2: Hyperspectral Spectral Angle Mapper - Julia Implementation
===============================================================================
Task: SAM classification on 224-band hyperspectral imagery
Dataset: NASA AVIRIS Cuprite (224 bands, freely available)
Metrics: Memory striding efficiency, zero-copy views, SIMD vectorization
Methodology: Chen & Revels (2016) - min time as primary estimator
===============================================================================
"""

using MAT
using Statistics
using LinearAlgebra
using SHA
using JSON3
using Random

include(joinpath(@__DIR__, "common_hash.jl"))

const RUNS = 5
const WARMUP = 2

function spectral_angle_mapper(pixel_spectra::Matrix{Float32}, reference_spectrum::Vector{Float32})
    epsilon = Float32(1e-8)
    dot_products = pixel_spectra * reference_spectrum
    pixel_norms = vec(sqrt.(sum(abs2, pixel_spectra, dims=2)))
    ref_norm = norm(reference_spectrum)
    cos_angles = dot_products ./ (pixel_norms .* ref_norm .+ epsilon)
    cos_angles = clamp.(cos_angles, -1.0f0, 1.0f0)
    angles = acos.(cos_angles)
    return angles
end

function process_chunked(data, reference_spectrum::Vector{Float32}, chunk_size=256)
    n_bands, n_rows, n_cols = size(data)
    
    sum_angles = Float32(0.0)
    sum_sq_angles = Float32(0.0)
    sum_min = Float32(Inf)
    sum_max = Float32(-Inf)
    count = 0
    pixels_processed = 0
    chunks_processed = 0
    
    for row_start in 1:chunk_size:n_rows
        for col_start in 1:chunk_size:n_cols
            row_end = min(row_start + chunk_size - 1, n_rows)
            col_end = min(col_start + chunk_size - 1, n_cols)
            
            @views chunk = data[:, row_start:row_end, col_start:col_end]
            
            chunk_perm = permutedims(collect(chunk), (2, 3, 1))
            n_pixels_chunk = (row_end - row_start + 1) * (col_end - col_start + 1)
            pixel_spectra = Float32.(reshape(chunk_perm, n_pixels_chunk, n_bands))
            
            sam_angles = spectral_angle_mapper(pixel_spectra, reference_spectrum)
            
            chunk_sum = sum(sam_angles)
            chunk_sum_sq = sum(abs2, sam_angles)
            sum_angles += chunk_sum
            sum_sq_angles += chunk_sum_sq
            sum_min = min(sum_min, minimum(sam_angles))
            sum_max = max(sum_max, maximum(sam_angles))
            count += length(sam_angles)
            pixels_processed += n_pixels_chunk
            chunks_processed += 1
        end
    end
    
    mean_angle = count > 0 ? sum_angles / count : Float32(0.0)
    std_angle = count > 0 ? sqrt(sum_sq_angles / count - mean_angle^2) : Float32(0.0)
    
    return (mean_sam=mean_angle, std_sam=std_angle, min_sam=sum_min, max_sam=sum_max,
            pixels_processed=pixels_processed, chunks_processed=chunks_processed)
end

function load_synthetic_hsi(n_bands=224, n_rows=512, n_cols=614)
    println("  Generating synthetic HSI data...")
    Random.seed!(42)
    x = collect(LinRange{Float32}(0, 4f0 * Float32(pi), n_cols))
    y = collect(LinRange{Float32}(0, 4f0 * Float32(pi), n_rows))
    xx = repeat(x', n_rows, 1)
    yy = repeat(y, 1, n_cols)
    signal = Float32.(0.3f0 .* sin.(xx .+ yy) .+ 0.2f0 .* sin.(2f0 .* xx .- yy))
    data = zeros(Float32, n_bands, n_rows, n_cols)
    spectral_pattern = Float32.(LinRange(0.8, 1.2, n_bands))
    for b in 1:n_bands
        noise = randn(Float32, n_rows, n_cols) .* 100f0
        data[b, :, :] = (signal .+ noise) .* spectral_pattern[b] .* 100f0 .+ 1000f0
    end
    println("  + Synthetic HSI: $n_bands bands × $n_rows × $n_cols")
    return data
end

function load_hsi_data(data_mode)
    if data_mode == "synthetic"
        return load_synthetic_hsi(), "synthetic"
    end
    hsi_path = joinpath(@__DIR__, "..", "data", "Cuprite.mat")
    if isfile(hsi_path) || data_mode == "real"
        try
            println("  Loading MAT file: $hsi_path")
            mat_file = matopen(hsi_path, "r")
            data_keys = keys(mat_file)
            data_key = first(data_keys)
            raw_data = read(mat_file, data_key)
            close(mat_file)
            if length(size(raw_data)) == 3 && size(raw_data, 3) == 224
                data = permutedims(raw_data, (3, 1, 2))
            else
                data = raw_data
            end
            data = Float32.(data)
            println("  + Real HSI: $(size(data, 1)) bands × $(size(data, 2)) × $(size(data, 3))")
            return data, "real"
        catch e
            if data_mode == "real"
                println("  x Real data load failed: $e")
                exit(1)
            end
            println("  - Real data unavailable ($e), using synthetic")
        end
    end
    return load_synthetic_hsi(), "synthetic"
end

function main()
    data_mode = "auto"
    for (i, arg) in enumerate(ARGS)
        if arg == "--data" && i < length(ARGS)
            data_mode = ARGS[i+1]
        end
    end
    
    println("\n[1/5] Initializing...")
    n_bands = 224
    reference_spectrum = collect(LinRange{Float32}(0.1, 0.9, n_bands))
    reference_spectrum ./= norm(reference_spectrum)
    println("  ✓ Reference spectrum: $n_bands bands")
    ref_hash = bytes2hex(sha256(reinterpret(UInt8, reference_spectrum)))[1:16]
    println("  ✓ Reference spectrum hash: $ref_hash")
    
    println("\n[2/5] Opening hyperspectral dataset...")
    hsi_path = joinpath(@__DIR__, "..", "data", "Cuprite.mat")
    if !isfile(hsi_path)
        println("ERROR: data file not found: $hsi_path")
        return 1
    end
    
    println("  ✓ Loading MAT file: $hsi_path")
    mat_file = matopen(hsi_path, "r")
    data_keys = keys(mat_file)
    data_key = first(data_keys)
    data = read(mat_file, data_key)
    close(mat_file)
    
    dims = size(data)
    if length(dims) == 3 && dims[3] == 224
        data = permutedims(data, (3, 1, 2))
    end
    n_bands = size(data, 1)
    n_rows = size(data, 2)
    n_cols = size(data, 3)
    println("  ✓ Dataset shape: $n_bands bands × $n_rows × $n_cols pixels")
    
    file_size_gb = filesize(hsi_path) / (1024^3)
    mem_info = Sys.free_memory() / (1024^3)
    println("  ✓ File size: $(round(file_size_gb, digits=2)) GB, Available RAM: $(round(mem_info, digits=2)) GB")
    
    println("\n[3/5] Running SAM classification ($RUNS runs, $WARMUP warmup)...")
    
    task = () -> process_chunked(data, reference_spectrum)
    
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
    
    println("\n[4/5] SAM classification results...")
    println("  ✓ Mean SAM angle: $(round(result.mean_sam, digits=6)) rad ($(round(rad2deg(result.mean_sam), digits=2))°)")
    println("  ✓ Std SAM angle: $(round(result.std_sam, digits=6)) rad")
    println("  ✓ Min SAM angle: $(round(result.min_sam, digits=6)) rad")
    println("  ✓ Max SAM angle: $(round(result.max_sam, digits=6)) rad")
    println("  ✓ Processed $(result.chunks_processed) chunks ($(result.pixels_processed) pixels)")
    
    println("\n[5/5] Validation and export...")
    hash_input = [result.mean_sam, result.std_sam, result.min_sam, result.max_sam]
    validation_hash = generate_hash(hash_input)
    println("  ✓ Validation hash: $validation_hash")
    
    results = Dict(
        "language" => "julia",
        "scenario" => "hyperspectral_sam",
        "data_source" => data_source,
        "data_description" => data_source == "real" ? "Cuprite.mat" : "synthetic $(n_bands)x$(size(data, 2))x$(size(data, 3))",
        "pixels_processed" => result.pixels_processed,
        "chunks_processed" => result.chunks_processed,
        "n_bands" => n_bands,
        "mean_sam_rad" => result.mean_sam,
        "std_sam_rad" => result.std_sam,
        "min_sam_rad" => result.min_sam,
        "max_sam_rad" => result.max_sam,
        "mean_sam_deg" => rad2deg(result.mean_sam),
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "validation_hash" => validation_hash,
        "reference_hash" => ref_hash
    )
    
    OUTPUT_DIR = joinpath(@__DIR__, "..", "results")
    VALIDATION_DIR = joinpath(@__DIR__, "..", "validation")
    mkpath(OUTPUT_DIR)
    mkpath(VALIDATION_DIR)
    
    open(joinpath(OUTPUT_DIR, "hsi_stream_julia.json"), "w") do f
        JSON3.pretty(f, results)
    end
    open(joinpath(VALIDATION_DIR, "raster_julia_results.json"), "w") do f
        JSON3.pretty(f, results)
    end
    
    println("✓ Results saved")
    println("=" ^ 70)
    println("JULIA - Scenario A.2: Hyperspectral SAM")
    println("=" ^ 70)

    println("\n[1/5] Initializing...")
    n_bands = 224
    reference_spectrum = collect(LinRange{Float32}(0.1, 0.9, n_bands))
    reference_spectrum ./= norm(reference_spectrum)
    println("  ✓ Reference spectrum: $n_bands bands")
    ref_hash = bytes2hex(sha256(reinterpret(UInt8, reference_spectrum)))[1:16]
    println("  ✓ Reference spectrum hash: $ref_hash")

    println("\n[2/5] Opening hyperspectral dataset...")
    data, data_source = load_hsi_data(data_mode)

exit(main())
