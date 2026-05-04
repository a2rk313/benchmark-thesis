#!/usr/bin/env julia
"""
SCENARIO F: Zonal Statistics - Julia Implementation
Tests: Polygon-based raster statistics (mean, std, sum over zones)

FAIRNESS PROTOCOL:
- Uses manual nested loops for rasterization (no GDAL/Terra engines).
- Uses center-pixel coordinate logic (r - 0.5) for validation parity.
- Defaults to real NLCD land cover data.
"""

using Statistics
using Random
using SHA
using JSON3
using DataFrames

const OUTPUT_DIR = "validation"
const RESULTS_DIR = "results"

include(joinpath(@__DIR__, "common_hash.jl"))

"""
Create rectangular bounding boxes. Matches the 'create_polygon_zones'
logic in Python/R for spatial parity.
    """
    function create_rectangular_zones(n_zones::Int=10)
        # Return as (id, xmin, ymin, xmax, ymax)
        zones = Tuple{Int, Float64, Float64, Float64, Float64}[]
        lat_step = 180.0 / n_zones
        lon_step = 360.0 / n_zones

        id = 1
        for i in 0:(n_zones-1)
            for j in 0:(n_zones-1)
                min_lon = -180.0 + j * lon_step
                max_lon = min_lon + lon_step
                min_lat = -90.0 + i * lat_step
                max_lat = min_lat + lat_step
                push!(zones, (id, min_lon, min_lat, max_lon, max_lat))
                id += 1
            end
        end
        return zones
    end

    """
    Manual Rasterization Loop.
    Directly tests Julia's loop performance against Python/R manual loops.
    """
    function rasterize_polygons_to_mask(zones, rows::Int, cols::Int)
        mask = zeros(Int32, rows, cols)
        lat_step = 180.0 / rows
        lon_step = 360.0 / cols

        for (zone_id, xmin, ymin, xmax, ymax) in zones
            # Calculate row/col ranges based on bounding box
            r0 = max(1, floor(Int, (90.0 - ymax) / lat_step) + 1)
            r1 = min(rows, ceil(Int, (90.0 - ymin) / lat_step))
            c0 = max(1, floor(Int, (xmin + 180.0) / lon_step) + 1)
            c1 = min(cols, ceil(Int, (xmax + 180.0) / lon_step))

            @inbounds for r in r0:r1
                lat = 90.0 - (r - 0.5) * lat_step # Pixel center
                for c in c0:c1
                    lon = -180.0 + (c - 0.5) * lon_step # Pixel center
                    if lon >= xmin && lon <= xmax && lat >= ymin && lat <= ymax
                        mask[r, c] = Int32(zone_id)
                    end
                end
            end
        end
        return mask
    end

    """
    Zonal Statistics calculation using Julia's native array views.
    """
    function calculate_zonal_stats(raster::Matrix{Float32}, mask::Matrix{Int32})
        unique_zones = filter(z -> z > 0, unique(mask))

        means = Float64[]
        stds = Float64[]

        for zone_id in unique_zones
            # Logical indexing is native and fair across all three languages
            values = raster[mask .== zone_id]

            if !isempty(values)
                push!(means, mean(values))
                push!(stds, std(values))
            else
                push!(means, 0.0)
                push!(stds, 0.0)
            end
        end
        return (means=means, stds=stds, zones=unique_zones)
    end

    function run_benchmark_task(func, runs, warmup)
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
        println("JULIA - Scenario F: Zonal Statistics (Fairness-Optimized)")
        println("=" ^ 70)

        # 1. Data Selection (Default: Real NLCD)
        data_mode = "auto"
        if "--data" in ARGS
            idx = findfirst(isequal("--data"), ARGS)
            data_mode = ARGS[idx + 1]
        end

        raster = nothing
        rows, cols = 600, 600
        data_source = "synthetic"

        if data_mode != "synthetic"
            nlcd_path = joinpath(@__DIR__, "..", "data", "nlcd", "nlcd_landcover.bin")
            hdr_path = replace(nlcd_path, ".bin" => ".hdr")

            if isfile(nlcd_path) && isfile(hdr_path)
                try
                    local r, c
                    for line in eachline(hdr_path)
                        if startswith(line, "samples") c = parse(Int, split(line, "=")[2]) end
                        if startswith(line, "lines") r = parse(Int, split(line, "=")[2]) end
                    end

                    raw_data = Vector{UInt8}(undef, r * c)
                    read!(nlcd_path, raw_data)
                    raster = reshape(Float32.(raw_data), r, c)
                    rows, cols = r, c
                    data_source = "real"
                    println("  ✓ Loaded real NLCD data: $(rows)x$(cols)")
                    catch e
                    println("  ⚠ Failed to load NLCD: $e")
                end
            end
        end

        if raster === nothing
            Random.seed!(42)
            raster = rand(Float64, rows, cols) .* 3000.0 |> Matrix{Float32}
            println("  → Created synthetic raster: $(rows)x$(cols)")
        end

        # 2. Geometry Creation
        zones = create_rectangular_zones(10)

        # 3. Benchmark: Mask Creation
        println("\n[1/2] Benchmarking Mask Creation...")
        m_times, mask = run_benchmark_task(() -> rasterize_polygons_to_mask(zones, rows, cols), 10, 2)
        mask_hash = generate_hash(mask)
        println("    Min Time: $(minimum(m_times))s")
        println("    Hash: $mask_hash")

        # 4. Benchmark: Zonal Stats
        println("\n[2/2] Benchmarking Zonal Statistics...")
        s_times, stats = run_benchmark_task(() -> calculate_zonal_stats(raster, mask), 10, 2)
        result_hash = generate_hash(stats.means)
        println("    Min Time: $(minimum(s_times))s")
        println("    Hash: $result_hash")

        # 5. Save Results
        output = Dict(
            "language" => "julia",
            "scenario" => "zonal_statistics",
            "data_source" => data_source,
            "results" => Dict(
                "mask_creation" => Dict("min_time_s" => minimum(m_times), "times" => m_times, "validation_hash" => mask_hash),
                "zonal_stats" => Dict("min_time_s" => minimum(s_times), "times" => s_times, "validation_hash" => result_hash)
                ),
            "combined_hash" => generate_hash([mask_hash, result_hash])
            )

            mkpath(RESULTS_DIR); mkpath(OUTPUT_DIR)
            open(joinpath(RESULTS_DIR, "zonal_stats_julia.json"), "w") do f JSON3.pretty(f, output) end
            open(joinpath(OUTPUT_DIR, "zonal_stats_julia_results.json"), "w") do f JSON3.pretty(f, output) end

            println("\n✓ Benchmark Complete. Results saved.")
    end

    main()
