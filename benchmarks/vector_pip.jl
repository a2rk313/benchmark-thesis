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
function haversine_vectorized(lat1::Vector{Float64}, lon1::Vector{Float64}, 
                               lat2::Vector{Float64}, lon2::Vector{Float64})
    R = 6371000.0  # Earth radius in meters
    
    # Convert to radians
    lat1_rad = deg2rad.(lat1)
    lat2_rad = deg2rad.(lat2)
    dlat = deg2rad.(lat2 .- lat1)
    dlon = deg2rad.(lon2 .- lon1)
    
    # Haversine formula
    a = sin.(dlat ./ 2.0).^2 .+ 
        cos.(lat1_rad) .* cos.(lat2_rad) .* 
        sin.(dlon ./ 2.0).^2
    
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
    
    # Load polygon dataset
    polys = GeoDataFrames.read("data/natural_earth_countries.gpkg")
    println("  ✓ Loaded $(nrow(polys)) polygons")
    
    # Load point dataset
    points_df = CSV.read("data/gps_points_1m.csv", DataFrame)
    println("  ✓ Loaded $(nrow(points_df)) points")
    
    # Convert to ArchGDAL points
    points_geom = [ArchGDAL.createpoint(row.lon, row.lat) for row in eachrow(points_df)]
    
    # =========================================================================
    # 2. Spatial Join (Point-in-Polygon) - Parallel Processing
    # =========================================================================
    println("\n[2/4] Performing spatial join (using $(Threads.nthreads()) threads)...")
    
    # Build spatial index using LibGEOS STRtree
    rtree = LibGEOS.STRtree(polys.geometry)
    
    # Pre-calculate centroids
    centroids = [ArchGDAL.centroid(geom) for geom in polys.geometry]
    
    # Prepare thread-safe storage
    n_points = length(points_geom)
    matched_indices = Vector{Union{Nothing, Int}}(nothing, n_points)
    
    # Parallel spatial join
    Threads.@threads for i in 1:n_points
        point = points_geom[i]
        
        # Query spatial index for candidate polygons
        candidates = LibGEOS.query(rtree, point)
        
        # Test exact topology (GEOS within predicate)
        for poly_idx in candidates
            if LibGEOS.within(point, polys.geometry[poly_idx])
                matched_indices[i] = poly_idx
                break  # First match is sufficient
            end
        end
    end
    
    # Filter to matched points only
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
    
    # Extract point coordinates
    point_lats = [points_df[i, :lat] for i in matched_point_indices]
    point_lons = [points_df[i, :lon] for i in matched_point_indices]
    
    # Extract centroid coordinates
    centroid_lats = [ArchGDAL.gety(centroids[idx], 0) for idx in matched_poly_indices]
    centroid_lons = [ArchGDAL.getx(centroids[idx], 0) for idx in matched_poly_indices]
    
    # Vectorized Haversine calculation
    distances = haversine_vectorized(point_lats, point_lons, centroid_lats, centroid_lons)
    
    # =========================================================================
    # 4. Results & Validation
    # =========================================================================
    println("\n[4/4] Computing metrics...")
    
    # Statistics
    total_distance = sum(distances)
    mean_distance = mean(distances)
    median_distance = median(distances)
    max_distance = maximum(distances)
    
    println("  ✓ Total distance: $(Int(round(total_distance))) meters")
    println("  ✓ Mean distance: $(Int(round(mean_distance))) meters")
    println("  ✓ Median distance: $(Int(round(median_distance))) meters")
    println("  ✓ Max distance: $(Int(round(max_distance))) meters")
    
    # Generate validation hash
    result_str = "$(round(total_distance, digits=6))_$(n_matches)_$(round(mean_distance, digits=6))"
    result_hash = bytes2hex(sha256(result_str))[1:16]
    
    println("  ✓ Validation hash: $result_hash")
    
    # Export results
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
    
    # Save results
    mkpath("validation")
    open("validation/vector_julia_results.json", "w") do f
        JSON3.write(f, results)
    end
    
    println("\n  ✓ Results saved to validation/vector_julia_results.json")
    println("=" ^ 70)
    
    return 0
end

# Run benchmark
exit(main())
