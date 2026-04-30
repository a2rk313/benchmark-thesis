#!/usr/bin/env julia
"""
SCENARIO: Vector Point-in-Polygon - Julia Implementation
Tests: Point-in-polygon spatial join performance

Uses vectorized spatial indexing for fair comparison with Python/R.
"""

using GeoDataFrames, DataFrames, CSV, ArchGDAL, LibGEOS, Statistics, JSON3, SHA

function haversine_vectorized(lat1, lon1, lat2, lon2)
    R = 6371000.0
    lat1_rad, lat2_rad = deg2rad.(lat1), deg2rad.(lat2)
    dlat, dlon = deg2rad.(lon2 .- lat1), deg2rad.(lon2 .- lon1)
    a = sin.(dlat ./ 2.0).^2 .+ cos.(lat1_rad) .* cos.(lat2_rad) .* sin.(dlon ./ 2.0).^2
    return R .* (2 .* atan.(sqrt.(a), sqrt.(1 .- a)))
end

function vectorized_point_in_polygon(points_lat, points_lon, geos_polys, tree)
    n_pts = length(points_lat)
    matched = BitVector(undef, n_pts)
    fill!(matched, false)

    @inbounds for i in 1:n_pts
        pt = LibGEOS.Point(points_lon[i], points_lat[i])
        candidate_idx = LibGEOS.query(tree, pt)
        for idx in candidate_idx
            if LibGEOS.within(pt, geos_polys[idx])
                matched[i] = true
                break
            end
        end
    end

    return matched
end

function run_benchmark(func, runs, warmup)
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
    println("JULIA - Scenario: Vector Point-in-Polygon")
    println("=" ^ 70)

    println("\n[1/3] Loading data...")
    polys = GeoDataFrames.read(joinpath(@__DIR__, "..", "data", "natural_earth_countries.gpkg"))
    points_df = CSV.read(joinpath(@__DIR__, "..", "data", "gps_points_1m.csv"), DataFrame)
    println("  ✓ Loaded $(nrow(polys)) polygons and $(nrow(points_df)) points")

    println("\n[2/3] Building spatial index...")
    t_build = time_ns()
    geos_polys = [LibGEOS.readgeom(ArchGDAL.toWKT(g)) for g in polys.geometry]
    tree = LibGEOS.STRtree(geos_polys)
    t_build = (time_ns() - t_build) / 1e9
    println("  ✓ STRtree built in $(round(t_build, digits=4))s")

    println("\n[3/3] Running point-in-polygon benchmark...")

    warmup = 2
    runs = 10

    points_lat = Vector{Float64}(points_df.lat)
    points_lon = Vector{Float64}(points_df.lon)

    pip_func = () -> vectorized_point_in_polygon(points_lat, points_lon, geos_polys, tree)

    times, matched = run_benchmark(pip_func, runs, warmup)
    n_matches = sum(matched)
    println("  ✓ Matches found: $n_matches")
    println("  ✓ Min time: $(minimum(times))s (primary)")
    println("  ✓ Mean time: $(mean(times))s ± $(std(times))s")

    result_hash = generate_hash([n_matches, mean(matched)])
    println("  ✓ Validation hash: $result_hash")

    results = Dict(
        "language" => "julia",
        "scenario" => "vector_pip",
        "n_points" => nrow(points_df),
        "n_polygons" => nrow(polys),
        "n_matches" => n_matches,
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "warmup" => warmup,
        "runs" => runs,
        "hash" => result_hash
    )

    mkpath("validation")
    mkpath("results")
    open("results/vector_pip_julia.json", "w") do f
        JSON3.pretty(f, results)
    end
    open("validation/vector_julia_results.json", "w") do f
        JSON3.pretty(f, results)
    end
    println("✓ Results saved")

    println("\n" * "=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)
end

main()