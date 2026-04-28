#!/usr/bin/env julia
"""
SCENARIO F: Zonal Statistics - Julia Implementation
Tests: Polygon-based raster statistics (mean, std, sum over zones)
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

function zonal_stats_implementation(raster::Matrix{Float32}, polys::DataFrame)
    # This implementation mimics the logic of standard GIS zonal stats
    # For each polygon, we calculate stats on the raster cells it covers
    # Note: In a real production scenario, we'd use a spatial index
    
    means = Float64[]
    counts = Int[]
    
    n_polys = nrow(polys)
    rows, cols = size(raster)
    
    # We'll use a simplified bounding-box approach for fairness with Python's basic loop
    # but still perform the actual polygon intersection check
    for geom in polys.geometry
        bbox = ArchGDAL.boundingbox(geom)
        
        # boundingbox might return a tuple or namedtuple - handle both
        if hasproperty(bbox, :min_x)
            xmin, xmax = bbox.min_x, bbox.max_x
            ymin, ymax = bbox.min_y, bbox.max_y
        else
            # Plain tuple: (min_x, min_y, max_x, max_y)
            xmin, ymin, xmax, ymax = bbox[1], bbox[2], bbox[3], bbox[4]
        end
        
        col_start = max(1, floor(Int, (xmin + 180) / 360 * cols))
        col_end = min(cols, ceil(Int, (xmax + 180) / 360 * cols))
        row_start = max(1, floor(Int, (90 - ymax) / 180 * rows))
        row_end = min(rows, ceil(Int, (90 - ymin) / 180 * rows))
        
        zone_values = Float32[]
        for r in row_start:row_end
            for c in col_start:col_end
                # Real polygon-point check using LibGEOS (not ArchGDAL.contains)
                # Note: This is where Julia's JIT and loops shine
                point = LibGEOS.createpoint(c/cols*360-180, 90-r/rows*180)
                if LibGEOS.contains(geom, point)
                    push!(zone_values, raster[r, c])
                end
            end
        end
        
        if !isempty(zone_values)
            push!(means, mean(zone_values))
            push!(counts, length(zone_values))
        else
            push!(means, 0.0)
            push!(counts, 0)
        end
    end
    
    return (means=means, counts=counts)
end

function main()
    println("=" ^ 70)
    println("JULIA - Scenario F: Zonal Statistics (Bare-Metal)")
    println("=" ^ 70)
    
    # 1. Load Data
    println("\n[1/4] Loading real-world polygons...")
    polys = GeoDataFrames.read(joinpath(@__DIR__, "..", "data", "natural_earth_countries.gpkg"))
    println("  ✓ Loaded $(nrow(polys)) country polygons")
    
    # 2. Create Raster
    rows, cols = 500, 500
    Random.seed!(42)
    raster = rand(Float32, rows, cols) .* 3000f0
    println("  ✓ Created synthetic raster: $rows x $cols cells")
    
    # 3. Benchmark
    println("\n[2/4] Running zonal statistics benchmark...")
    
    # Warmup
    zonal_stats_implementation(raster, first(polys, 5))
    
    t_start = time_ns()
    results = zonal_stats_implementation(raster, polys)
    t_end = time_ns()
    
    duration = (t_end - t_start) / 1e9
    println("  ✓ Completed in $(round(duration, digits=4)) seconds")
    
    # 4. Hash and Export
    result_hash = bytes2hex(sha256(JSON3.write(results.means)))[1:16]
    println("  ✓ Validation hash: $result_hash")
    
    output = Dict(
        "language" => "julia",
        "scenario" => "zonal_stats",
        "min_time_s" => duration,
        "polygons" => nrow(polys),
        "hash" => result_hash
    )
    
    mkpath("results")
    open("results/zonal_stats_julia.json", "w") do f
        JSON3.write(f, output)
    end
    println("✓ Results saved to results/zonal_stats_julia.json")
end

main()
