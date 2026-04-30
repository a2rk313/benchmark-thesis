#!/usr/bin/env julia
"""
SCENARIO G: Coordinate Reprojection - Julia Implementation
Tests: EPSG:4326 <-> UTM/Web Mercator reprojection performance

Uses PROJ library (Proj.jl) for fair comparison with Python's pyproj.
"""

using Statistics
using Random
using SHA
using JSON3

# Try to use PROJ bindings
PROJ_AVAILABLE = false
try
    using Proj
    PROJ_AVAILABLE = true
catch
end

const OUTPUT_DIR = "validation"
const RESULTS_DIR = "results"

include(joinpath(@__DIR__, "common_hash.jl"))

deg2rad(deg::T) where T<:Number = deg * pi / 180.0
rad2deg(rad::T) where T<:Number = rad * 180.0 / pi

function reproject_wgs84_to_utm_zone(lat, lon, zone)
    """Reproject a single point to its UTM zone using PROJ."""
    epsg = zone <= 0 ? "326$zone" : "327$zone"
    epsg_code = lat >= 0 ? "326$zone" : "327$zone"

    if PROJ_AVAILABLE
        t = Proj.Transformer(from="EPSG:4326", to=epsg_code)
        x, y = t.transform(lon, lat)
        return x, y
    else
        return wgs84_to_utm_manual_single(lat, lon, zone)
    end
end

function reproject_wgs84_to_utm_batch(lat::AbstractVector{Float64}, lon::AbstractVector{Float64})
    """Batch reproject to UTM zones."""
    n = length(lat)
    x = Vector{Float64}(undef, n)
    y = Vector{Float64}(undef, n)
    zones = Vector{Int}(undef, n)

    if PROJ_AVAILABLE
        zone_cache = Dict{Int, Any}()

        @inbounds for i in 1:n
            zone = clamp(Int(floor((lon[i] + 180) / 6) + 1), 1, 60)
            epsg = lat[i] >= 0 ? "326$zone" : "327$zone"

            if !haskey(zone_cache, epsg)
                zone_cache[epsg] = Proj.Transformer(from="EPSG:4326", to=epsg)
            end

            x[i], y[i] = zone_cache[epsg].transform(lon[i], lat[i])
            zones[i] = zone
        end
    else
        zones = clamp.(Int.(floor.((lon .+ 180) ./ 6) .+ 1), 1, 60)

        @inbounds for i in 1:n
            x[i], y[i] = wgs84_to_utm_manual_single(lat[i], lon[i], zones[i])
        end
    end

    return (x=x, y=y, zones=zones)
end

function wgs84_to_utm_manual_single(lat, lon, zone)
    """Manual UTM conversion (fallback if PROJ unavailable)."""
    a = 6378137.0
    f = 1.0 / 298.257223563
    k0 = 0.9996
    e = sqrt(2*f - f^2)
    e2 = e^2
    e_prime2 = e2 / (1.0 - e2)

    lat_r = deg2rad(lat)
    lon_r = deg2rad(lon)
    lambda0 = deg2rad((zone - 1) * 6 - 180 + 3)

    sin_lat = sin(lat_r)
    cos_lat = cos(lat_r)
    tan_lat = tan(lat_r)
    N = a / sqrt(1.0 - e2 * sin_lat^2)
    T = tan_lat^2
    C = e_prime2 * cos_lat^2
    A = cos_lat * (lon_r - lambda0)

    M = a * ((1.0 - e2/4.0 - 3.0*e2^2/64.0) * lat_r -
              (3.0*e2/8.0 + 3.0*e2^2/32.0) * sin(2.0*lat_r) +
              (15.0*e2^2/256.0) * sin(4.0*lat_r))

    x_utm = k0 * N * (A + (1.0 - T + C) * A^3/6.0 +
                      (5.0 - 18.0*T + T^2 + 72.0*C - 58.0*e_prime2) * A^5/120.0)
    y_utm = k0 * (M + N * tan_lat * (A^2/2.0 +
                      (5.0 - T + 9.0*C + 4.0*C^2) * A^4/24.0 +
                      (61.0 - 58.0*T + T^2 + 600.0*C - 3300.0*e_prime2) * A^6/720.0))

    x = x_utm + 500000.0
    y = lat < 0.0 ? y_utm + 10000000.0 : y_utm

    return x, y
end

function reproject_to_web_mercator(lat::AbstractVector{Float64}, lon::AbstractVector{Float64})
    """Reproject to Web Mercator (EPSG:3857)."""
    n = length(lat)
    x = Vector{Float64}(undef, n)
    y = Vector{Float64}(undef, n)

    if PROJ_AVAILABLE
        t = Proj.Transformer(from="EPSG:4326", to="EPSG:3857")
        @inbounds for i in 1:n
            x[i], y[i] = t.transform(lon[i], lat[i])
        end
    else
        a = 6378137.0
        @inbounds for i in 1:n
            lat_r = deg2rad(lat[i])
            lon_r = deg2rad(lon[i])
            x[i] = a * lon_r
            y[i] = a * log(tan(pi/4 + lat_r/2))
        end
    end

    return (x=x, y=y)
end

function generate_test_points(n_points::Int)
    Random.seed!(42)
    lat = rand(-90.0:1e-6:90.0, n_points)
    lon = rand(-180.0:1e-6:180.0, n_points)
    return (lat=lat, lon=lon)
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

function run_reprojection_benchmark()
    println("=" ^ 70)
    println("JULIA - Scenario G: Coordinate Reprojection")
    println("Using PROJ library: $PROJ_AVAILABLE")
    println("=" ^ 70)

    sizes = [1000, 5000, 10000]
    results = Dict()
    all_hashes = String[]

    for size in sizes
        println("\n[Testing with $size points]")
        println("-" ^ 40)

        points = generate_test_points(size)

        println("  Web Mercator (EPSG:4326 -> 3857)...")

        merc_task() = reproject_to_web_mercator(points.lat, points.lon)

        times, merc_result = run_benchmark(merc_task, 5, 2)
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
            "points_per_second" => round(Int, size / minimum(times)),
            "hash" => merc_hash
        )

        println("  UTM (zone-optimized)...")

        utm_task() = reproject_wgs84_to_utm_batch(points.lat, points.lon)

        times, _ = run_benchmark(utm_task, 3, 1)

        println("    Min: $(minimum(times))s (primary)")
        println("    Mean: $(mean(times))s ± $(std(times))s")
        println("    Rate: $(round(Int, size / minimum(times))) points/sec")

        results["utm_$size"] = Dict(
            "n_points" => size,
            "min_time_s" => minimum(times),
            "mean_time_s" => mean(times),
            "std_time_s" => std(times),
            "points_per_second" => round(Int, size / minimum(times))
        )
    end

    println("\n" * "=" ^ 70)
    println("SAVING RESULTS...")
    println("=" ^ 70)

    mkpath(OUTPUT_DIR)
    mkpath(RESULTS_DIR)

    output_data = Dict(
        "language" => "julia",
        "scenario" => "coordinate_reprojection",
        "library" => PROJ_AVAILABLE ? "Proj.jl" : "manual",
        "results" => results,
        "all_hashes" => all_hashes,
        "combined_hash" => generate_hash(all_hashes)
    )

    open("$OUTPUT_DIR/reprojection_julia_results.json", "w") do f
        JSON3.pretty(f, output_data)
    end

    println("Results saved")
    println("Combined validation hash: $(output_data["combined_hash"])")

    println("\n" * "=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)

    return output_data
end

run_reprojection_benchmark()