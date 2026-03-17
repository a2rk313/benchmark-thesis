#!/usr/bin/env julia
"""
===============================================================================
SCENARIO B: Complex Vector Operations - Julia Implementation
===============================================================================
Task: Point-in-Polygon spatial join + Haversine distance calculation
Dataset: 1M GPS points × Natural Earth countries (high-vertex complexity)
Metrics: Computational throughput, GEOS interface efficiency, parallelization
===============================================================================
"""

using GeoDataFrames
using DataFrames
using CSV
using ArchGDAL
using LibGEOS
using Statistics
using LinearAlgebra
using SHA
using JSON3
using Base.Threads

"""
Vectorized Haversine distance calculation

Args:
    lat1, lon1: Point coordinates (arrays)
    lat2, lon2: Centroid coordinates (arrays)

Returns:
    Distance in meters (array)
"""
function haversine_vectorized(
    lat1::Vector{Float64}, lon1::Vector{Float64},
    lat2::Vector{Float64}, lon2::Vector{Float64}
)
    R = 6_371_000.0  # Earth radius in meters

    lat1_rad = deg2rad.(lat1)
    lat2_rad = deg2rad.(lat2)
    dlat = deg2rad.(lat2 .- lat1)
    dlon = deg2rad.(lon2 .- lon1)

    a = sin.(dlat ./ 2).^2 .+
        cos.(lat1_rad) .* cos.(lat2_rad) .* sin.(dlon ./ 2).^2

    c = 2 .* atan.(sqrt.(a), sqrt.(1 .- a))

    return R .* c
end

function main()
    println("=" ^ 70)
    println("JULIA - Scenario B: Vector Point-in-Polygon + Haversine")
    println("=" ^ 70)

    # =========================================================================
    # 1. Data Loading
    # =========================================================================
    println("\n[1/4] Loading data...")

    polys_df = GeoDataFrames.read("data/natural_earth_countries.gpkg")
    n_polys = nrow(polys_df)
    println("  ✓ Loaded $n_polys polygons")

    println("  Converting polygons to LibGEOS format...")
    libgeos_polys = [
        LibGEOS.readgeom(ArchGDAL.toWKT(geom))
        for geom in polys_df.geometry
    ]
    println("  ✓ Converted $n_polys polygons")

    println("  Building spatial index...")
    rtree = LibGEOS.STRtree(libgeos_polys)
    println("  ✓ Spatial index built")

    println("  Computing centroids...")
    centroids = [LibGEOS.centroid(poly) for poly in libgeos_polys]

    centroid_x = Vector{Float64}(undef, length(centroids))
    centroid_y = Vector{Float64}(undef, length(centroids))

    for (i, c) in enumerate(centroids)
        x, y = LibGEOS.getcoord(c)
        centroid_x[i] = x
        centroid_y[i] = y
    end
    println("  ✓ Centroids computed")

    points_df = CSV.read("data/gps_points_1m.csv", DataFrame)
    n_points = nrow(points_df)
    println("  ✓ Loaded $n_points points")

    # =========================================================================
    # 2. Spatial Join (Point-in-Polygon)
    # =========================================================================
    println("\n[2/4] Performing spatial join (using $(Threads.nthreads()) threads)...")

    test_point = LibGEOS.Point(points_df.lon[1], points_df.lat[1])
    test_candidates = LibGEOS.query(rtree, test_point)
    returns_indices = !isempty(test_candidates) && test_candidates[1] isa Integer

    if returns_indices
        println("  ✓ query returns indices (modern LibGEOS)")
    else
        println("  ✓ query returns geometries (older LibGEOS) – building index map")
        geom_index = IdDict{Any, Int}()
        for (i, geom) in enumerate(libgeos_polys)
            geom_index[geom] = i
        end
    end

    matched_indices = Vector{Union{Nothing, Int}}(undef, n_points)
    fill!(matched_indices, nothing)

    Threads.@threads for i in 1:n_points
        lon = points_df.lon[i]
        lat = points_df.lat[i]
        point = LibGEOS.Point(lon, lat)

        candidates = LibGEOS.query(rtree, point)

        if returns_indices
            for poly_idx in candidates
                if LibGEOS.within(point, libgeos_polys[poly_idx])
                    matched_indices[i] = poly_idx
                    break
                end
            end
        else
            for cand in candidates
                poly_idx = geom_index[cand]
                if LibGEOS.within(point, cand)
                    matched_indices[i] = poly_idx
                    break
                end
            end
        end
    end

    matched_mask = matched_indices .!== nothing
    matched_point_indices = findall(matched_mask)
    matched_poly_indices = matched_indices[matched_mask]

    n_matches = length(matched_point_indices)
    println("  ✓ Matched $n_matches points to polygons")
    println("  ✓ Match rate: $(round(100 * n_matches / n_points, digits=2))%")

    # =========================================================================
    # 3. Distance Calculation
    # =========================================================================
    println("\n[3/4] Calculating Haversine distances...")

    point_lats = points_df.lat[matched_point_indices]
    point_lons = points_df.lon[matched_point_indices]

    centroid_lats = centroid_y[matched_poly_indices]
    centroid_lons = centroid_x[matched_poly_indices]

    distances = haversine_vectorized(
        point_lats, point_lons,
        centroid_lats, centroid_lons
    )

    # =========================================================================
    # 4. Results & Validation
    # =========================================================================
    println("\n[4/4] Computing metrics...")

    total_distance = sum(distances)
    mean_distance = mean(distances)
    median_distance = median(distances)
    max_distance = maximum(distances)

    println("  ✓ Total distance: $(Int(round(total_distance))) meters")
    println("  ✓ Mean distance: $(Int(round(mean_distance))) meters")
    println("  ✓ Median distance: $(Int(round(median_distance))) meters")
    println("  ✓ Max distance: $(Int(round(max_distance))) meters")

    result_str = "$(round(total_distance, digits=6))_$(n_matches)_$(round(mean_distance, digits=6))"
    result_hash = bytes2hex(sha256(result_str))[1:16]

    println("  ✓ Validation hash: $result_hash")

    results = Dict(
        "language" => "julia",
        "scenario" => "vector_pip",
        "points_processed" => n_points,
        "matches_found" => n_matches,
        "total_distance_m" => total_distance,
        "mean_distance_m" => mean_distance,
        "median_distance_m" => median_distance,
        "max_distance_m" => max_distance,
        "validation_hash" => result_hash,
        "threads_used" => Threads.nthreads()
    )

    mkpath("validation")
    open("validation/vector_julia_results.json", "w") do f
        JSON3.write(f, results)
    end

    println("\n  ✓ Results saved to validation/vector_julia_results.json")
    println("=" ^ 70)

    return 0
end

exit(main())
