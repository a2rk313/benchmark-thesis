#!/usr/bin/env julia
using GeoDataFrames, DataFrames, CSV, ArchGDAL, LibGEOS, Statistics, JSON3, SHA

function haversine_vectorized(lat1, lon1, lat2, lon2)
    R = 6371000.0
    lat1_rad, lat2_rad = deg2rad.(lat1), deg2rad.(lat2)
    dlat, dlon = deg2rad.(lat2 .- lat1), deg2rad.(lon2 .- lon1)
    a = sin.(dlat ./ 2.0).^2 .+ cos.(lat1_rad) .* cos.(lat2_rad) .* sin.(dlon ./ 2.0).^2
    return R .* (2 .* atan.(sqrt.(a), sqrt.(1 .- a)))
end

function main()
    polys = GeoDataFrames.read(joinpath(@__DIR__, "..", "data", "natural_earth_countries.gpkg"))
    points_df = CSV.read(joinpath(@__DIR__, "..", "data", "gps_points_1m.csv"), DataFrame)
    
    # Create Spatial Index (STRtree) for fairness
    geos_polys = [LibGEOS.readgeom(ArchGDAL.toWKT(g)) for g in polys.geometry]
    tree = LibGEOS.STRtree(geos_polys)
    
    matched_pt_indices = Int[]
    matched_poly_indices = Int[]
    
    for (i, row) in enumerate(eachrow(points_df))
        pt = LibGEOS.Point(row.lon, row.lat)
        # Query tree for candidate polygons - this returns polygon OBJECTS, not indices
        candidate_objs = LibGEOS.query(tree, pt)
        for obj in candidate_objs
            # Just check within directly, no need for identity matching
            if LibGEOS.within(pt, obj)
                push!(matched_pt_indices, i)
                push!(matched_poly_indices, length(matched_pt_indices))  # Track as match count
            end
        end
    end
    
    # Calculate Distances
    centroids = [LibGEOS.centroid(g) for g in geos_polys]
    p_lat, p_lon = points_df[matched_pt_indices, :lat], points_df[matched_pt_indices, :lon]
    c_lat = [LibGEOS.getY(centroids[i]) for i in matched_poly_indices]
    c_lon = [LibGEOS.getX(centroids[i]) for i in matched_poly_indices]
    dist = haversine_vectorized(p_lat, p_lon, c_lat, c_lon)
    
    # Save Results
    results = Dict("language"=>"julia", "total_dist"=>sum(dist), "matches"=>length(dist))
    mkpath("validation")
    open("validation/vector_julia_results.json", "w") do f; JSON3.write(f, results); end
end
main()