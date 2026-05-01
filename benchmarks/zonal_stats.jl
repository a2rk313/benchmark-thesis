#!/usr/bin/env julia
"""
SCENARIO F: Zonal Statistics - Julia Implementation
Tests: Polygon-based raster statistics (mean, std, sum over zones)

Uses IDENTICAL rectangular polygon zones as Python and R for valid comparison.
"""

using Statistics
using Random
using SHA
using JSON3
using ArchGDAL
using GeoDataFrames
using DataFrames

const OUTPUT_DIR = "validation"
const RESULTS_DIR = "results"

include(joinpath(@__DIR__, "common_hash.jl"))

function create_rectangular_zones_simple(n_zones::Int=10)
    zones = Tuple{Float64,Float64,Float64,Float64}[]  # (min_lon, min_lat, max_lon, max_lat)
    lat_step = 180.0 / n_zones
    lon_step = 360.0 / n_zones

    for i in 0:(n_zones-1)
        for j in 0:(n_zones-1)
            min_lon = -180.0 + j * lon_step
            max_lon = min_lon + lon_step
            min_lat = -90.0 + i * lat_step
            max_lat = min_lat + lat_step
            push!(zones, (min_lon, min_lat, max_lon, max_lat))
        end
    end
    return zones
end


function rasterize_polygons_to_mask(zones::Vector{Tuple{Float64,Float64,Float64,Float64}}, rows::Int, cols::Int)
    mask = zeros(Int32, rows, cols)
    lat_step = 180.0 / rows
    lon_step = 360.0 / cols

    for (zone_id, (xmin, ymin, xmax, ymax)) in enumerate(zones)
        r0 = max(1, floor(Int, (90.0 - ymax) / lat_step) + 1)
        r1 = min(rows, ceil(Int, (90.0 - ymin) / lat_step))
        c0 = max(1, floor(Int, (xmin + 180.0) / lon_step) + 1)
        c1 = min(cols, ceil(Int, (xmax + 180.0) / lon_step))

        for r in r0:r1
            for c in c0:c1
                lat = 90.0 - (r - 0.5) * lat_step
                lon = -180.0 + (c - 0.5) * lon_step
                if lon >= xmin && lon <= xmax && lat >= ymin && lat <= ymax
                    mask[r, c] = zone_id
                end
            end
        end
    end

    return mask
end


function vectorized_zonal_stats(raster::Matrix{Float32}, mask::Matrix{Int32})
    unique_zones = filter(z -> z > 0, unique(vec(mask)))
    n_zones = length(unique_zones)

    means = Float64[]
    stds = Float64[]
    sums = Float64[]
    counts = Int[]

    for zone_id in unique_zones
        zone_mask = mask .== zone_id
        values = raster[zone_mask]
        if length(values) > 0
            push!(means, mean(values))
            push!(stds, std(values))
            push!(sums, sum(values))
            push!(counts, length(values))
        else
            push!(means, 0.0)
            push!(stds, 0.0)
            push!(sums, 0.0)
            push!(counts, 0)
        end
    end

    return (means=means, stds=stds, sums=sums, counts=counts, zones=unique_zones)
end


function run_benchmark_zonal(func, runs, warmup)
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


function main()
    println("=" ^ 70)
    println("JULIA - Scenario F: Zonal Statistics (Bare-Metal)")
    println("=" ^ 70)

    rows, cols = 600, 600
    n_zones = 10

    Random.seed!(42)
    raster = rand(Float32, rows, cols) .* 3000f0
    println("\n[1/4] Created synthetic raster: $rows x $cols cells")

    println("\n[2/4] Creating rectangular polygon zones (consistent with Python/R)...")
    zones = create_rectangular_zones_simple(n_zones)
    println("  ✓ Created $(length(zones)) rectangular polygon zones")

    println("\n[3/4] Running zonal statistics benchmark...")

    warmup = 2
    runs = 10

    mask_times, mask = run_benchmark_zonal(() -> rasterize_polygons_to_mask(zones, rows, cols), runs, warmup)
    println("  ✓ Mask creation: min=$(minimum(mask_times))s, mean=$(mean(mask_times))s")

    stats_times, results = run_benchmark_zonal(() -> vectorized_zonal_stats(raster, mask), runs, warmup)
    println("  ✓ Zonal stats: min=$(minimum(stats_times))s, mean=$(mean(stats_times))s")

    result_hash = generate_hash(results.means)
    println("  ✓ Validation hash: $result_hash")

    output = Dict(
        "language" => "julia",
        "scenario" => "zonal_stats",
        "zone_type" => "rectangular_polygons",
        "n_zones" => n_zones * n_zones,
        "min_time_s" => minimum(stats_times),
        "mean_time_s" => mean(stats_times),
        "std_time_s" => std(stats_times),
        "polygons" => length(zones),
        "hash" => result_hash,
        "warmup" => warmup,
        "runs" => runs,
    )

    mkpath("results")
    open("results/zonal_stats_julia.json", "w") do f
        JSON3.pretty(f, output)
    end
    mkpath("validation")
    open("validation/zonal_stats_julia_results.json", "w") do f
        JSON3.pretty(f, output)
    end
    println("✓ Results saved to results/zonal_stats_julia.json")
    println("\n" * "=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)
end

main()
