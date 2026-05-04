#!/usr/bin/env julia
"""
===============================================================================
SCENARIO C: Spatial Interpolation - Julia Implementation
===============================================================================
Task: Inverse Distance Weighting (IDW) interpolation on scattered points
Dataset: 50,000 random points → 1000x1000 grid interpolation
Metrics: Computational throughput, numerical efficiency, parallelization
Methodology: Chen & Revels (2016) - min time as primary estimator
===============================================================================
"""

using NearestNeighbors
using Statistics
using Random
using LinearAlgebra
using JSON3
using SHA
using CSV
using DataFrames

include(joinpath(@__DIR__, "common_hash.jl"))

const RUNS = 5
const WARMUP = 2

# Changed signature: values can be any AbstractVector{Float64}
function idw_interpolation(points::Matrix{Float64}, values::AbstractVector{Float64},
                           grid_x::Matrix{Float64}, grid_y::Matrix{Float64};
                           power::Float64=2.0, neighbors::Int=12)
    tree = KDTree(points')
    grid_points = hcat(vec(grid_x), vec(grid_y))'
    idxs, dists = knn(tree, grid_points, neighbors, true)
    n_grid = size(grid_points, 2)
    interpolated = zeros(Float64, n_grid)
    for i in 1:n_grid
        distances = max.(dists[i], 1e-10)
        weights = 1.0 ./ (distances .^ power)
        weights ./= sum(weights)
        interpolated[i] = sum(weights .* values[idxs[i]])
    end
    return reshape(interpolated, size(grid_x))
end

function generate_synthetic_idw_points(n_points=50000)
    Random.seed!(42)
    x = rand(Float64, n_points) .* 1000.0
    y = rand(Float64, n_points) .* 1000.0
    values = 100.0 .* sin.(x ./ 200.0 .+ 10.0) .* cos.(y ./ 200.0) .+ 50.0 .* sin.(x ./ 50.0) .+ 20.0 .* randn(n_points)
    return x, y, values
end

function load_idw_data(data_mode)
    csv_path = joinpath(@__DIR__, "..", "data", "synthetic", "idw_points_50k.csv")
    if data_mode == "synthetic"
        x, y, values = generate_synthetic_idw_points()
        return x, y, values, "synthetic"
    end
    if isfile(csv_path) || data_mode == "real"
        try
            df = CSV.read(csv_path, DataFrame)
            println("  ✓ Loaded $(nrow(df)) points from shared CSV")
            # Convert columns to plain Vector{Float64} for safety
            x = Vector{Float64}(df.x)
            y = Vector{Float64}(df.y)
            v = Vector{Float64}(df.value)
            return x, y, v, "real"
            catch e
            if data_mode == "real"
                println("  x Real data load failed: $e")
                exit(1)
            end
            println("  - CSV unavailable ($e), using synthetic")
        end
    end
    x, y, values = generate_synthetic_idw_points()
    return x, y, values, "synthetic"
end

function main()
    data_mode = "auto"
    for (i, arg) in enumerate(ARGS)
        if arg == "--data" && i < length(ARGS)
            data_mode = ARGS[i+1]
        end
    end

    println("=" ^ 70)
    println("JULIA - Scenario C: Spatial Interpolation (IDW)")
    println("=" ^ 70)

    println("\n[1/3] Loading scattered point data...")
    x, y, values, data_source = load_idw_data(data_mode)
    n_points = length(values)
    points = hcat(x, y)
    println("  ✓ Loaded $n_points scattered points ($data_source)")
    println("  ✓ Value range: [$(minimum(values)), $(maximum(values))]")

    println("\n[2/3] Creating interpolation grid...")
    grid_resolution = 1000
    grid_x = repeat(range(0, 1000, length=grid_resolution)', grid_resolution, 1)
    grid_y = repeat(range(0, 1000, length=grid_resolution), 1, grid_resolution)
    println("  ✓ Grid size: $grid_resolution × $grid_resolution")
    println("  ✓ Total interpolation points: $(grid_resolution^2)")

    println("\n[3/3] Performing IDW interpolation ($RUNS runs, $WARMUP warmup)...")

    task = () -> idw_interpolation(points, values, grid_x, grid_y, power=2.0, neighbors=12)

    for _ in 1:WARMUP
        task()
    end

    GC.gc()
    times = Float64[]
    interpolated = nothing
    for _ in 1:RUNS
        t_start = time_ns()
        interpolated = task()
        t_end = time_ns()
        push!(times, (t_end - t_start) / 1e9)
    end

    points_per_second = (grid_resolution^2) / minimum(times)

    println("  ✓ Min: $(minimum(times))s (primary)")
    println("  ✓ Mean: $(mean(times))s ± $(std(times))s")
    println("  ✓ Processing rate: $(round(Int, points_per_second)) grid points/second")

    println("\nComputing domain statistics...")
    mean_value = mean(interpolated)
    std_value = std(interpolated)
    median_value = median(interpolated)
    println("  ✓ Mean: $(round(mean_value, digits=2)), Std: $(round(std_value, digits=2)), Median: $(round(median_value, digits=2))")

    result_hash = generate_hash(interpolated)
    println("  ✓ Validation hash: $result_hash")

    results = Dict(
        "language" => "julia",
        "scenario" => "interpolation_idw",
        "data_source" => data_source,
        "data_description" => data_source == "real" ? "idw_points_50k.csv" : "synthetic 50K points (seed 42)",
        "n_points" => n_points,
        "grid_size" => grid_resolution,
        "total_interpolated" => grid_resolution^2,
        "min_time_s" => minimum(times),
        "mean_time_s" => mean(times),
        "std_time_s" => std(times),
        "max_time_s" => maximum(times),
        "times" => times,
        "points_per_second" => points_per_second,
        "mean_value" => mean_value,
        "std_value" => std_value,
        "median_value" => median_value,
        "validation_hash" => result_hash
        )

    OUTPUT_DIR = joinpath(@__DIR__, "..", "results")
    VALIDATION_DIR = joinpath(@__DIR__, "..", "validation")
    mkpath(OUTPUT_DIR)
    mkpath(VALIDATION_DIR)

    open(joinpath(OUTPUT_DIR, "interpolation_idw_julia.json"), "w") do f
        JSON3.pretty(f, results)
    end
    open(joinpath(VALIDATION_DIR, "interpolation_julia_results.json"), "w") do f
        JSON3.pretty(f, results)
    end

    println("\n✓ Results saved")
    println("=" ^ 70)
    println("Note: Minimum times are primary metrics (Chen & Revels 2016)")
    println("=" ^ 70)

    return 0
end

exit(main())
