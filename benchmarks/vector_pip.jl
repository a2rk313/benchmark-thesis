#!/usr/bin/env julia
"""
SCENARIO: Vector Point-in-Polygon - Julia Implementation (LibGEOS)

FAIRNESS NOTES (vs R/Python):
1. STRtree is now built INSIDE run_pip_and_distances — included in timing,
consistent with R (terra::extract) and Python (gpd.sjoin).
2. geom_to_idx is pre-built OUTSIDE the timing loop — it is static metadata
(polygon index → geometry mapping), analogous to R's poly_idx column and
Python's GeoDataFrame integer index, both of which are pre-existing.
3. GC.gc() called before timing loop — consistent with R (gc()) and Python
(gc.collect()).
4. PIP loop uses Threads.@threads to use all available cores, consistent with
R (terra uses all cores by default) and Python (GEOS/GDAL multi-threaded).
Launch Julia with: julia --threads auto scenario_b.jl
or set: export JULIA_NUM_THREADS=auto
"""

using GeoDataFrames, DataFrames, CSV, ArchGDAL, LibGEOS, Statistics, JSON3, SHA, Random

include(joinpath(@__DIR__, "common_hash.jl"))

const RUNS   = 10
const WARMUP = 2

# ------------------------------------------------------------
# Fast Haversine
# ------------------------------------------------------------
function haversine_vectorized(lat1, lon1, lat2, lon2)
    R = 6371000.0
    lat1_rad = deg2rad.(lat1)
    lat2_rad = deg2rad.(lat2)
    dlat = deg2rad.(lat2 .- lat1)
    dlon = deg2rad.(lon2 .- lon1)
    a = sin.(dlat ./ 2).^2 .+ cos.(lat1_rad) .* cos.(lat2_rad) .* sin.(dlon ./ 2).^2
    return R .* (2 .* atan.(sqrt.(a), sqrt.(1 .- a)))
end

# ------------------------------------------------------------
# Point-in-polygon using LibGEOS spatial index.
# geom_to_idx is pre-built outside the timed loop and passed in — it is
# static polygon metadata, not part of the spatial query operation.
# tree is built by the caller (run_pip_and_distances) inside the timed region.
# ------------------------------------------------------------
function vectorized_point_in_polygon(points_lat, points_lon,
                                     geom_to_idx::Base.IdDict,
                                     tree)
    n_pts      = length(points_lat)
    matched    = zeros(Bool, n_pts)
    matched_poly = zeros(Int, n_pts)

    # Threads.@threads: each iteration writes to its own index (i) with its own
    # local LibGEOS.Point — no shared mutable state, so no locking needed.
    # STRtree queries are read-only and GEOS STRtree is thread-safe for concurrent
    # reads. Launch Julia with --threads auto (or JULIA_NUM_THREADS=auto).
    Threads.@threads for i in 1:n_pts
        pt = LibGEOS.Point(points_lon[i], points_lat[i])
        candidates = LibGEOS.query(tree, pt)
        for g in candidates
            if LibGEOS.within(pt, g)
                matched[i]      = true
                matched_poly[i] = geom_to_idx[g]
                break
            end
        end
    end
    return matched, matched_poly
end

# ------------------------------------------------------------
# FAIRNESS: STRtree is built here, inside the timed region, consistent with
# R (terra::extract rebuilds its index each call) and Python (gpd.sjoin
# rebuilds its STRtree each call).
# ------------------------------------------------------------
function run_pip_and_distances(points_lat, points_lon,
                               geoms::AbstractVector{<:LibGEOS.AbstractGeometry},
                               geom_to_idx::Base.IdDict,
                               centroid_lons::Vector{Float64},
                               centroid_lats::Vector{Float64})
    # Spatial index build is timed — consistent with R and Python.
    tree = LibGEOS.STRtree(geoms)

    matched, matched_poly = vectorized_point_in_polygon(
        points_lat, points_lon, geom_to_idx, tree)
    n_matches = sum(matched)

    if n_matches == 0
        return (n_matches=0, total_distance=0.0, mean_distance=0.0,
                median_distance=0.0, max_distance=0.0, distances=Float64[])
    end

    matched_idx = findall(matched)
    p_lats      = points_lat[matched_idx]
    p_lons      = points_lon[matched_idx]
    poly_idx    = matched_poly[matched_idx]

    c_lons = centroid_lons[poly_idx]
    c_lats = centroid_lats[poly_idx]

    distances = haversine_vectorized(p_lats, p_lons, c_lats, c_lons)

    return (n_matches=n_matches, total_distance=sum(distances),
            mean_distance=mean(distances), median_distance=median(distances),
            max_distance=maximum(distances), distances=distances)
end

# ------------------------------------------------------------
# Convert ArchGDAL geometry to LibGEOS (via WKT)
# ------------------------------------------------------------
function to_libgeos(g::ArchGDAL.IGeometry)
    LibGEOS.readgeom(ArchGDAL.toWKT(g))
end

# ------------------------------------------------------------
# Synthetic data — centroids as rectangle midpoints.
# ------------------------------------------------------------
function generate_synthetic_polygons(n_polys=50)
    polys  = DataFrame(name=String[], geometry=LibGEOS.Polygon[])
    c_lons = Float64[]
    c_lats = Float64[]

    lat_step = 180.0 / (n_polys ÷ 2 + 1)
    lon_step = 360.0 / (n_polys ÷ 2 + 1)
    idx = 0
    Random.seed!(42)
    for i in 0:(n_polys ÷ 2)
        for j in 0:(n_polys ÷ 2)
            idx >= n_polys && break
            min_lon = -180.0 + j * lon_step + rand() * 4 - 2
            max_lon = min_lon + lon_step + rand() * 4 - 2
            min_lat = -90.0  + i * lat_step + rand() * 4 - 2
            max_lat = min_lat + lat_step + rand() * 4 - 2
            min_lon = max(-180.0, min(min_lon, 180.0))
            max_lon = max(-180.0, min(max_lon, 180.0))
            min_lat = max(-90.0,  min(min_lat,  90.0))
            max_lat = max(-90.0,  min(max_lat,  90.0))
            if max_lon > min_lon && max_lat > min_lat
                ring = LibGEOS.LinearRing([
                    [min_lon, min_lat], [max_lon, min_lat],
                    [max_lon, max_lat], [min_lon, max_lat], [min_lon, min_lat]
                    ])
                poly = LibGEOS.Polygon([ring])
                push!(polys, (name="Country_$(idx+1)", geometry=poly))
                push!(c_lons, (min_lon + max_lon) / 2.0)
                push!(c_lats, (min_lat + max_lat) / 2.0)
                idx += 1
            end
        end
    end
    return polys, c_lons, c_lats
end

function generate_synthetic_points(n_points=1_000_000)
    Random.seed!(42)
    lats = rand(n_points) .* 180.0 .- 90.0
    lons = rand(n_points) .* 360.0 .- 180.0
    return DataFrame(lat=lats, lon=lons)
end

# ------------------------------------------------------------
# Data loading — returns centroid arrays alongside polygon data.
# Centroids are computed from ArchGDAL geometries BEFORE LibGEOS conversion.
# ------------------------------------------------------------
function load_vector_data(data_mode)
    if data_mode == "synthetic"
        println("  Generating synthetic polygons and points...")
        polys, c_lons, c_lats = generate_synthetic_polygons()
        points_df = generate_synthetic_points()
        return polys, points_df, "synthetic", c_lons, c_lats
    end

    poly_path   = joinpath(@__DIR__, "..", "data", "natural_earth_countries.gpkg")
    points_path = joinpath(@__DIR__, "..", "data", "gps_points_1m.csv")
    poly_exists   = isfile(poly_path)
    points_exists = isfile(points_path)

    if (poly_exists && points_exists) || data_mode == "real"
        try
            if !poly_exists && data_mode == "real"
                println("  x Real polygon data not found: $poly_path"); exit(1)
            end
            if !points_exists && data_mode == "real"
                println("  x Real GPS data not found: $points_path"); exit(1)
            end
            if poly_exists && points_exists
                println("  Loading real Natural Earth polygons + GPS points...")
                polys     = GeoDataFrames.read(poly_path)
                points_df = CSV.read(points_path, DataFrame)

                println("  Computing centroids via ArchGDAL...")
                arch_centroids = [ArchGDAL.centroid(g) for g in polys.geometry]
                    c_lons = Float64[ArchGDAL.getx(c, 0) for c in arch_centroids]
                        c_lats = Float64[ArchGDAL.gety(c, 0) for c in arch_centroids]

                            println("  Converting geometries to LibGEOS...")
                            lib_geoms = [to_libgeos(g) for g in polys.geometry]
                                polys.geometry = lib_geoms
                                GC.gc()
                                return polys, points_df, "real", c_lons, c_lats
                            end
                            catch e
                            if data_mode == "real"
                                println("  x Real data load failed: $e"); exit(1)
                            end
                            println("  - Real data unavailable ($e), using synthetic")
                        end
                    end

                    println("  -> Using synthetic data")
                    polys, c_lons, c_lats = generate_synthetic_polygons()
                    points_df = generate_synthetic_points()
                    return polys, points_df, "synthetic", c_lons, c_lats
                end

                # ------------------------------------------------------------
                # Main benchmark
                # ------------------------------------------------------------
                function main()
                    data_mode = "auto"
                    for (i, arg) in enumerate(ARGS)
                        if arg == "--data" && i < length(ARGS)
                            data_mode = ARGS[i+1]
                        end
                    end

                    println("=" ^ 70)
                    println("JULIA - Scenario: Vector Point-in-Polygon")
                    println("  Threads: $(Threads.nthreads())")
                    println("=" ^ 70)

                    println("\n[1/4] Loading data...")
                    polys, points_df, data_source, centroid_lons, centroid_lats =
                        load_vector_data(data_mode)
                    println("  ✓ Loaded $(nrow(polys)) polygons and $(nrow(points_df)) points ($data_source)")
                    println("  ✓ Precomputed $(length(centroid_lons)) polygon centroids")

                    geoms = collect(polys.geometry)

                    # FAIRNESS: geom_to_idx is static polygon metadata — pre-built once outside
                    # the timing loop. Equivalent to R's poly_idx column and Python's DataFrame
                    # index, both of which are pre-existing before the timed region.
                    println("\n[2/4] Pre-building geometry→index map (static metadata, not timed)...")
                    geom_to_idx = Base.IdDict{LibGEOS.AbstractGeometry, Int}()
                    for (idx, g) in enumerate(geoms)
                        geom_to_idx[g] = idx
                    end
                    println("  ✓ Mapped $(length(geom_to_idx)) geometries")

                    # NOTE: STRtree is NOT built here — it is built inside run_pip_and_distances
                    # so that index construction is included in timing for all three languages.

                    println("\n[3/4] Running PIP + Haversine ($RUNS runs, $WARMUP warmup)...")

                    points_lat = Vector{Float64}(points_df.lat)
                    points_lon = Vector{Float64}(points_df.lon)

                    task = () -> run_pip_and_distances(
                        points_lat, points_lon, geoms, geom_to_idx,
                        centroid_lons, centroid_lats)

                    for _ in 1:WARMUP
                        task()
                    end

                    # FAIRNESS: force GC before timing loop, consistent with R (gc()) and
                    # Python (gc.collect()).
                    GC.gc()

                    times  = Float64[]
                    result = nothing
                    for _ in 1:RUNS
                        t_start = time_ns()
                        result  = task()
                        push!(times, (time_ns() - t_start) / 1e9)
                    end

                    println("  ✓ Min:  $(round(minimum(times), digits=4))s (primary)")
                    println("  ✓ Mean: $(round(mean(times), digits=4))s ± $(round(std(times), digits=4))s")
                    println("  ✓ Matches found: $(result.n_matches)")

                    println("\n[4/4] Distance statistics and validation...")
                    println("  ✓ Total distance: $(round(result.total_distance, digits=0)) m")
                    println("  ✓ Mean distance:   $(round(result.mean_distance,  digits=2)) m")
                    println("  ✓ Median distance: $(round(result.median_distance, digits=2)) m")
                    println("  ✓ Max distance:    $(round(result.max_distance,    digits=2)) m")

                    result_hash = generate_hash(result.distances)
                    println("  ✓ Validation hash: $result_hash")

                    results = Dict(
                        "language"          => "julia",
                        "scenario"          => "vector_pip",
                        "data_source"       => data_source,
                        "data_description"  => data_source == "real" ?
                        "Natural Earth + GPS 1M" : "synthetic",
                        "n_points"          => nrow(points_df),
                        "n_polygons"        => nrow(polys),
                        "matches_found"     => result.n_matches,
                        "total_distance_m"  => result.total_distance,
                        "mean_distance_m"   => result.mean_distance,
                        "median_distance_m" => result.median_distance,
                        "max_distance_m"    => result.max_distance,
                        "min_time_s"        => minimum(times),
                        "mean_time_s"       => mean(times),
                        "std_time_s"        => std(times),
                        "max_time_s"        => maximum(times),
                        "times"             => times,
                        "validation_hash"   => result_hash
                        )

                    OUTPUT_DIR     = joinpath(@__DIR__, "..", "results")
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
