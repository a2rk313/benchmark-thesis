#!/usr/bin/env julia
"""
SCENARIO G: Coordinate Reprojection - Julia Implementation
Tests: EPSG:4326 <-> UTM/Web Mercator reprojection performance
Uses manual formulas matching pyproj/EPSG standards (avoids GDAL latitude range errors).
"""

using Statistics
using Random
using SHA
using JSON3
using CSV
using DataFrames
using ArchGDAL

# --- GDAL/PROJ INITIALIZATION ---
const PROJ_PATH = joinpath(ArchGDAL.GDAL.PROJ_jll.artifact_dir, "share", "proj")
ArchGDAL.GDAL.osrsetprojsearchpaths([PROJ_PATH])
ArchGDAL.GDAL.gdalallregister()
ArchGDAL.GDAL.cplsetconfigoption("OGR_ENABLE_PARTIAL_REPROJECTION", "YES")
# --------------------------------

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

# Spherical Mercator — identical to pyproj EPSG:3857.
# R = WGS84 semi-major axis used by the standard.
function reproject_to_web_mercator(lat::AbstractVector{Float64}, lon::AbstractVector{Float64})
    R = 6378137.0
    x = R .* (lon .* (π / 180.0))
    y = R .* log.(tan.(π / 4.0 .+ clamp.(lat, -85.051129, 85.051129) .* (π / 360.0)))
    return (x=x, y=y)
end

# Transverse Mercator / UTM — matches R's wgs84_to_utm_manual and Python's pyproj
# for points within the valid UTM latitude range.
function utm_point(lat_deg::Float64, lon_deg::Float64)
    a  = 6378137.0
    f  = 1.0 / 298.257223563
    k0 = 0.9996
    e2 = 2f - f^2
    n  = f / (2 - f)

    zone     = clamp(Int(floor((lon_deg + 180) / 6)) + 1, 1, 60)
    lon0_deg = (zone - 1) * 6 - 180 + 3
    lat_r    = lat_deg  * (π / 180.0)
    dlon_r   = (lon_deg - lon0_deg) * (π / 180.0)

    N  = a / sqrt(1 - e2 * sin(lat_r)^2)
    T  = tan(lat_r)^2
    C  = (e2 / (1 - e2)) * cos(lat_r)^2
    A  = cos(lat_r) * dlon_r

    # Meridional arc
    e4 = e2^2; e6 = e2^3
    M  = a * ((1 - e2/4 - 3e4/64 - 5e6/256) * lat_r
              - (3e2/8 + 3e4/32 + 45e6/1024) * sin(2lat_r)
              + (15e4/256 + 45e6/1024) * sin(4lat_r)
              - (35e6/3072) * sin(6lat_r))

    x = k0 * N * (A + (1 - T + C) * A^3/6 +
        (5 - 18T + T^2 + 72C - 58*(e2/(1-e2))) * A^5/120) + 500000.0

    y = k0 * (M + N * tan(lat_r) * (A^2/2 + (5 - T + 9C + 4C^2) * A^4/24 +
        (61 - 58T + T^2 + 600C - 330*(e2/(1-e2))) * A^6/720))
        if lat_deg < 0
            y += 10_000_000.0
        end

        return x, y, zone
end

function reproject_wgs84_to_utm_batch(lat::AbstractVector{Float64}, lon::AbstractVector{Float64})
    n = length(lat)
    x = Vector{Float64}(undef, n)
    y = Vector{Float64}(undef, n)
    zones = Vector{Int}(undef, n)
    @inbounds for i in 1:n
        x[i], y[i], zones[i] = utm_point(lat[i], lon[i])
    end
    return (x=x, y=y, zones=zones)
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

    all_lat, all_lon, data_source = load_reprojection_data(data_mode)

    sizes = [1000, 5000, 10000, 50000, 100000, 500000]
    results = Dict()
    all_hashes = String[]

    for size in sizes
        println("\n[Testing with $size points]")
        println("-" ^ 40)

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
            "n_points"        => size,
            "min_time_s"      => minimum(times),
            "mean_time_s"     => mean(times),
            "std_time_s"      => std(times),
            "median_time_s"   => median(times),
            "max_time_s"      => maximum(times),
            "points_per_sec"  => size / minimum(times),
            "times"           => times,
            "validation_hash" => merc_hash
            )

        println("  UTM Zones (EPSG:4326 -> UTM)...")
        utm_task() = reproject_wgs84_to_utm_batch(points.lat, points.lon)
        GC.gc()
        times, utm_result = run_benchmark(utm_task, 5, 2)
        n100 = min(100, size)
        utm_hash = generate_hash(vcat(utm_result.x[1:n100], utm_result.y[1:n100]))
        push!(all_hashes, utm_hash)
        println("    Min: $(minimum(times))s (primary)")
        println("    Mean: $(mean(times))s ± $(std(times))s")
        println("    Rate: $(round(Int, size / minimum(times))) points/sec")
        println("    Hash: $utm_hash")

        results["utm_$size"] = Dict(
            "n_points"        => size,
            "min_time_s"      => minimum(times),
            "mean_time_s"     => mean(times),
            "std_time_s"      => std(times),
            "median_time_s"   => median(times),
            "max_time_s"      => maximum(times),
            "points_per_sec"  => size / minimum(times),
            "times"           => times,
            "validation_hash" => utm_hash
            )
    end

    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)

    output_data = Dict(
        "language"         => "julia",
        "scenario"         => "reprojection",
        "data_source"      => data_source,
        "data_description" => data_source == "real" ? "GPS points (1M)" : "synthetic (1M, seed 42)",
        "n_points"         => length(all_lat),
        "results"          => results,
        "all_hashes"       => all_hashes,
        "combined_hash"    => generate_hash(all_hashes)
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

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
