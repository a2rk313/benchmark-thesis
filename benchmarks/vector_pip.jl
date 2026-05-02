#!/usr/bin/env julia
"""
SCENARIO: Vector Point-in-Polygon - Julia Implementation
Tests: Point-in-polygon spatial join performance

Uses vectorized spatial indexing for fair comparison with Python/R.
Methodology: Chen & Revels (2016) - min time as primary estimator
"""

using GeoDataFrames, DataFrames, CSV, ArchGDAL, LibGEOS, Statistics, JSON3, SHA, Random

include(joinpath(@__DIR__, "common_hash.jl"))

const RUNS = 10
const WARMUP = 2

function haversine_vectorized(lat1, lon1, lat2, lon2)
    R = 6371000.0
    lat1_rad = deg2rad.(lat1)
    lat2_rad = deg2rad.(lat2)
    dlat = deg2rad.(lat2 .- lat1)
    dlon = deg2rad.(lon2 .- lon1)
    a = sin.(dlat ./ 2.0).^2 .+ cos.(lat1_rad) .* cos.(lat2_rad) .* sin.(dlon ./ 2.0).^2
    return R .* (2 .* atan.(sqrt.(a), sqrt.(1 .- a)))
end

function vectorized_point_in_polygon(points_lat, points_lon, geos_polys, tree)
    n_pts = length(points_lat)
    matched = BitVector(undef, n_pts)
    fill!(matched, false)
    matched_poly = zeros(Int, n_pts)  # Store indices, not polygons
    
    # Build reverse index: geometry -> index for O(1) lookup
    geom_to_idx = Dict{LibGEOS.AbstractGeometry, Int}()
    for (idx, geom) in enumerate(geos_polys)
        geom_to_idx[geom] = idx
    end
    
    @inbounds for i in 1:n_pts
        pt = LibGEOS.Point(points_lon[i], points_lat[i])
        candidate_geoms = LibGEOS.query(tree, pt)
        for geom in candidate_geoms
            if LibGEOS.within(pt, geom)
                matched[i] = true
                # Look up index from reverse index (O(1) instead of O(n))
                if haskey(geom_to_idx, geom)
                    matched_poly[i] = geom_to_idx[geom]
                end
                break
            end
        end
    end
    
    return matched, matched_poly
end

function run_pip_and_distances(points_lat, points_lon, geos_polys, polys, tree)
    matched, matched_poly = vectorized_point_in_polygon(points_lat, points_lon, geos_polys, tree)
    n_matches = sum(matched)

    if n_matches == 0
        return (n_matches=0, total_distance=0.0, mean_distance=0.0,
                median_distance=0.0, max_distance=0.0, distances=Float64[])
    end

    matched_indices = findall(matched)
    point_lats = points_lat[matched_indices]
    point_lons = points_lon[matched_indices]
    
    poly_indices = matched_poly[matched_indices]
    # Get centroid coordinates using LibGEOS functions
    centroid_coords = [
        begin
            centroid = LibGEOS.centroid(geos_polys[i])
            (LibGEOS.getY(centroid.ptr, 1), LibGEOS.getX(centroid.ptr, 1))
        end
        for i in poly_indices if i > 0
    ]
    centroid_lats = [c[1] for c in centroid_coords]
    centroid_lons = [c[2] for c in centroid_coords]

    distances = haversine_vectorized(point_lats, point_lons, centroid_lats, centroid_lons)

    (n_matches=n_matches, total_distance=sum(distances), mean_distance=mean(distances),
     median_distance=median(distances), max_distance=maximum(distances), distances=distances)
end

function generate_synthetic_polygons(n_polys=50)
    polys = DataFrame(name=String[], geometry=LibGEOS.Polygon[])
    lat_step = 180.0 / (n_polys ÷ 2 + 1)
    lon_step = 360.0 / (n_polys ÷ 2 + 1)
    idx = 0
    Random.seed!(42)
    for i in 0:(n_polys ÷ 2)
        for j in 0:(n_polys ÷ 2)
            idx >= n_polys && break
            min_lon = -180.0 + j * lon_step + rand() * 4.0 - 2.0
            max_lon = min_lon + lon_step + rand() * 4.0 - 2.0
            min_lat = -90.0 + i * lat_step + rand() * 4.0 - 2.0
            max_lat = min_lat + lat_step + rand() * 4.0 - 2.0
            min_lon = max(-180.0, min(min_lon, 180.0))
            max_lon = max(-180.0, min(max_lon, 180.0))
            min_lat = max(-90.0, min(min_lat, 90.0))
            max_lat = max(-90.0, min(max_lat, 90.0))
            if max_lon > min_lon && max_lat > min_lat
                # Create polygon with correct coordinate format (vector of rings)
                exterior_ring = [
                    [min_lon, min_lat], [max_lon, min_lat],
                    [max_lon, max_lat], [min_lon, max_lat], [min_lon, min_lat]
                ]
                coords = [exterior_ring]  # Vector of rings (first is exterior)
                ring = LibGEOS.Polygon(coords)
                push!(polys, (name="Country_$(idx+1)", geometry=ring))
                idx += 1
            end
        end
    end
    return polys
end

function generate_synthetic_points(n_points=1_000_000)
    Random.seed!(42)
    lats = rand(n_points) .* 180.0 .- 90.0
    lons = rand(n_points) .* 360.0 .- 180.0
    return DataFrame(lat=lats, lon=lons)
end

function load_vector_data(data_mode)
    if data_mode == "synthetic"
        println("  Generating synthetic polygons and points...")
        polys = generate_synthetic_polygons()
        points_df = generate_synthetic_points()
        return polys, points_df, "synthetic"
    end
    poly_path = joinpath(@__DIR__, "..", "data", "natural_earth_countries.gpkg")
    points_path = joinpath(@__DIR__, "..", "data", "gps_points_1m.csv")
    poly_exists = isfile(poly_path)
    points_exists = isfile(points_path)
    if (poly_exists && points_exists) || data_mode == "real"
        try
            if !poly_exists && data_mode == "real"
                println("  x Real polygon data not found: $poly_path")
                exit(1)
            end
            if !points_exists && data_mode == "real"
                println("  x Real GPS data not found: $points_path")
                exit(1)
            end
            if poly_exists && points_exists
                println("  Loading real Natural Earth polygons + GPS points...")
                polys = GeoDataFrames.read(poly_path)
                points_df = CSV.read(points_path, DataFrame)
                return polys, points_df, "real"
            end
        catch e
            if data_mode == "real"
                println("  x Real data load failed: $e")
                exit(1)
            end
            println("  - Real data unavailable ($e), using synthetic")
        end
    end
    println("  → Using synthetic data")
    polys = generate_synthetic_polygons()
    points_df = generate_synthetic_points()
    return polys, points_df, "synthetic"
end

function main()
    data_mode = "auto"
    for (i, arg) in enumerate(ARGS)
        if arg == "--data" && i < length(ARGS)
            data_mode = ARGS[i+1]
        end
    end

    println("=" ^ 70)
    println("JULIA - Scenario: Vector Point-in-Polygon")
    println("=" ^ 70)

    println("\n[1/4] Loading data...")
    polys, points_df, data_source = load_vector_data(data_mode)
    println("  ✓ Loaded $(nrow(polys)) polygons and $(nrow(points_df)) points ($data_source)")

    println("\n[2/4] Building spatial index...")
    t_build = time_ns()
    # Use LibGEOS geometries directly (no need to convert to WKT and back)
    geos_polys = [g for g in polys.geometry]
    tree = LibGEOS.STRtree(geos_polys)
    t_build = (time_ns() - t_build) / 1e9
    println("  ✓ STRtree built in $(round(t_build, digits=4))s")

    println("\n[3/4] Running PIP + Haversine ($RUNS runs, $WARMUP warmup)...")

    points_lat = Vector{Float64}(points_df.lat)
    points_lon = Vector{Float64}(points_df.lon)

    task = () -> run_pip_and_distances(points_lat, points_lon, geos_polys, polys, tree)

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
    println("  ✓ Matches found: $(result.n_matches)")

    println("\n[4/4] Distance statistics and validation...")
    println("  ✓ Total distance: $(round(result.total_distance, digits=0)) m")
    println("  ✓ Mean distance: $(round(result.mean_distance, digits=2)) m")
    println("  ✓ Median distance: $(round(result.median_distance, digits=2)) m")
    println("  ✓ Max distance: $(round(result.max_distance, digits=2)) m")

    result_hash = generate_hash(result.distances)
    println("  ✓ Validation hash: $result_hash")

    results = Dict(
        "language" => "julia",
        "scenario" => "vector_pip",
        "data_source" => data_source,
        "data_description" => data_source == "real" ? "Natural Earth + GPS 1M" : "synthetic polygons + 1M points (seed 42)",
        "n_points" => nrow(points_df),
        "n_polygons" => nrow(polys),
        "n_matches" => result.n_matches,
        "matches_found" => result.n_matches,
        "total_distance_m" => result.total_distance,
        "mean_distance_m" => result.mean_distance,
        "median_distance_m" => result.median_distance,
        "max_distance_m" => result.max_distance,
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "validation_hash" => result_hash
    )

    OUTPUT_DIR = joinpath(@__DIR__, "..", "results")
    VALIDATION_DIR = joinpath(@__DIR__, "..", "validation")
    mkpath(OUTPUT_DIR)
    mkpath(VALIDATION_DIR)

    open(joinpath(OUTPUT_DIR, "vector_pip_julia.json"), "w") do f
        JSON3.pretty(f, results)
    end
    open(joinpath(VALIDATION_DIR, "vector_julia_results.json"), "w") do f
        JSON3.pretty(f, results)
    end

    println("✓ Results saved")
    println("\n" * "=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)
end

main()
