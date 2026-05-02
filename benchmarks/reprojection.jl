#!/usr/bin/env julia
"""
SCENARIO G: Coordinate Reprojection - Julia Implementation
Tests: EPSG:4326 <-> UTM/Web Mercator reprojection performance

Uses ArchGDAL for fair comparison with Python's pyproj.
"""

using Statistics
using Random
using SHA
using JSON3
using CSV
using DataFrames
using ArchGDAL

const OUTPUT_DIR = "validation"
const RESULTS_DIR = "results"

include(joinpath(@__DIR__, "common_hash.jl"))

function load_reprojection_data(data_mode)
    if data_mode == "synthetic"
        println("  Generating synthetic test points (1M, seed 42)...")
        Random.seed!(42)
        lat = rand(Float64, 1_000_000) .* 180.0 .- 90.0
        lon = rand(Float64, 1_000_000) .* 360.0 .- 180.0
        return lat, lon, "synthetic"
    end
    gps_path = joinpath(@__DIR__, "..", "data", "gps_points_1m.csv")
    if isfile(gps_path) || data_mode == "real"
        try
            println("  Loading GPS points: $gps_path")
            df = CSV.read(gps_path, DataFrame)
            lat = Vector{Float64}(df.lat)
            lon = Vector{Float64}(df.lon)
            println("  ✓ Loaded $(length(lat)) real GPS points")
            return lat, lon, "real"
        catch e
            if data_mode == "real"
                println("  x Real data load failed: $e")
                exit(1)
            end
            println("  - Real data unavailable ($e), using synthetic")
        end
    end
    Random.seed!(42)
    lat = rand(Float64, 1_000_000) .* 180.0 .- 90.0
    lon = rand(Float64, 1_000_000) .* 360.0 .- 180.0
    return lat, lon, "synthetic"
end

function generate_test_points(n_points::Int)
    Random.seed!(42)
    lat = rand(-90.0:1e-6:90.0, n_points)
    lon = rand(-180.0:1e-6:180.0, n_points)
    return (lat=lat, lon=lon)
end

deg2rad(deg::T) where T<:Number = deg * pi / 180.0
rad2deg(rad::T) where T<:Number = rad * 180.0 / pi

function reproject_wgs84_to_utm_batch(lat::AbstractVector{Float64}, lon::AbstractVector{Float64})
    n = length(lat)
    x = Vector{Float64}(undef, n)
    y = Vector{Float64}(undef, n)
    zones = Vector{Int}(undef, n)
    
    # Cache for different UTM zone transformations
    zone_cache = Dict{Int, ArchGDAL.SpatialRef}()
    
    @inbounds for i in 1:n
        zone = clamp(Int(floor((lon[i] + 180) / 6)) + 1, 1, 60)
        epsg = lat[i] >= 0 ? 32600 + zone : 32700 + zone
        
        if !haskey(zone_cache, epsg)
            sp = ArchGDAL.SpatialRef()
            ArchGDAL.importEPSG!(sp, epsg)
            zone_cache[epsg] = sp
        end
        
        src = ArchGDAL.SpatialRef()
        ArchGDAL.importEPSG!(src, 4326)
        dst = zone_cache[epsg]
        transform = ArchGDAL.CoordinateTransform(src, dst, false)
        
        x[i], y[i] = ArchGDAL.transform!(transform, lon[i], lat[i])
        zones[i] = zone
    end
    return (x=x, y=y, zones=zones)
end

function reproject_to_web_mercator(lat::AbstractVector{Float64}, lon::AbstractVector{Float64})
    n = length(lat)
    x = Vector{Float64}(undef, n)
    y = Vector{Float64}(undef, n)
    
    src = ArchGDAL.SpatialRef()
    ArchGDAL.importEPSG!(src, 4326)
    dst = ArchGDAL.SpatialRef()
    ArchGDAL.importEPSG!(dst, 3857)
    transform = ArchGDAL.CoordinateTransform(src, dst, false)
    
    @inbounds for i in 1:n
        x[i], y[i] = ArchGDAL.transform!(transform, lon[i], lat[i])
    end
    return (x=x, y=y)
end

function run_benchmark(func, runs::Int=10, warmup::Int=2)
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

function run_reprojection_benchmark(data_mode="auto")
    println("=" ^ 70)
    println("JULIA - Scenario G: Coordinate Reprojection")
    println("Using ArchGDAL (matching Python pyproj)")
    println("=" ^ 70)
    
    # Load data once based on mode
    all_lat, all_lon, data_source = load_reprojection_data(data_mode)
    
    sizes = [1000, 5000, 10000, 50000, 100000, 500000]
    results = Dict()
    all_hashes = String[]
    
    for size in sizes
        println("\n[Testing with $size points]")
        println("-" ^ 40)
        
        # Subset loaded data or generate synthetic for this size
        if size <= length(all_lat)
            points = (lat=all_lat[1:size], lon=all_lon[1:size])
        else
            points = generate_test_points(size)
        end
        
        println("  Web Mercator (EPSG:4326 -> 3857)...")
        
        merc_task() = reproject_to_web_mercator(points.lat, points.lon)
        
        GC.gc()
        times, merc_result = run_benchmark(merc_task, 10, 2)
        merc_hash = generate_hash([mean(merc_result.x), mean(merc_result.y)])
        push!(all_hashes, merc_hash)
        
        println("    Min: $(minimum(times))s (primary)")
        println("    Mean: $(mean(times))s ± $(std(times))s")
        println("    Rate: $(round(Int, size / minimum(times))) points/sec")
        println("    Hash: $merc_hash")
        
        results["mercator_$size"] = Dict(
            "n_points" => size,
            "min_time_s" => minimum(times),
            "mean_time_s" => mean(times),
            "std_time_s" => std(times),
            "median_time_s" => median(times),
            "max_time_s" => maximum(times),
            "points_per_sec" => size / minimum(times),
            "times" => times,
            "validation_hash" => merc_hash
        )
        
        println("  UTM Zones (EPSG:4326 -> UTM)...")
        
        utm_task() = reproject_wgs84_to_utm_batch(points.lat, points.lon)
        
        GC.gc()
        times, utm_result = run_benchmark(utm_task, 10, 2)
        utm_hash = generate_hash([mean(utm_result.x), mean(utm_result.y)])
        push!(all_hashes, utm_hash)
        
        println("    Min: $(minimum(times))s (primary)")
        println("    Mean: $(mean(times))s ± $(std(times))s")
        println("    Rate: $(round(Int, size / minimum(times))) points/sec")
        println("    Hash: $utm_hash")
        
        results["utm_$size"] = Dict(
            "n_points" => size,
            "min_time_s" => minimum(times),
            "mean_time_s" => mean(times),
            "std_time_s" => std(times),
            "median_time_s" => median(times),
            "max_time_s" => maximum(times),
            "points_per_sec" => size / minimum(times),
            "times" => times,
            "validation_hash" => utm_hash
        )
    end
    
    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)
    
    output_data = Dict(
        "language" => "julia",
        "scenario" => "reprojection",
        "data_source" => data_source,
        "data_description" => data_source == "real" ? "GPS points (1M)" : "synthetic (1M, seed 42)",
        "n_points" => length(all_lat),
        "results" => results,
        "all_hashes" => all_hashes,
        "combined_hash" => generate_hash(all_hashes)
    )
    
    mkpath(OUTPUT_DIR)
    mkpath(RESULTS_DIR)
    
    open(joinpath(OUTPUT_DIR, "reprojection_julia_results.json"), "w") do f
        JSON3.pretty(f, output_data)
    end
    
    println("✓ Results saved to: $(joinpath(OUTPUT_DIR, "reprojection_julia_results.json"))")
    println("✓ Combined validation hash: $(generate_hash(all_hashes))")
    
    println("\nNote: Minimum times are primary metrics (Chen & Revels 2016)")
end

function main()
    data_mode = "auto"
    for (i, arg) in enumerate(ARGS)
        if arg == "--data" && i < length(ARGS)
            data_mode = ARGS[i+1]
        end
    end
    
    run_reprojection_benchmark(data_mode)
end

# Entry point
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
