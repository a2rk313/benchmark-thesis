#!/usr/bin/env julia
"""
================================================================================
Data Scaling Benchmark Framework — All 9 Thesis Scenarios (Julia)
================================================================================

Runs benchmarks at multiple data scales to:
1. Validate algorithmic complexity via log-log regression
2. Identify performance cliffs and memory bottlenecks
3. Follow Tedesco et al. (2025) methodology (k=1,2,3,4 scaling factors)
4. Cover all 9 benchmark scenarios across the thesis

Methodology:
  - Minimum time as primary estimator (Chen & Revels 2016)
  - Data generation OUTSIDE timed section (only computation measured)
  - Consistent random seeds for reproducibility at each scale
  - Log-log regression: log(t) = k * log(n) + c, where k = scaling exponent

Output:
  - results/scaling/{scenario}_scaling_julia.json (per-scenario)
  - results/scaling/combined_scaling_summary_julia.json (all scenarios)
================================================================================
"""

using LinearAlgebra
using Statistics
using Random
using Printf
using Dates

# Optional packages for spatial scenarios
const HAS_NEIGHBORS = try
    using NearestNeighbors
    true
catch
    false
end

const HAS_LIBGEOS = try
    using LibGEOS
    using DataFrames
    true
catch
    false
end

const HAS_ARCHGDAL = try
    using ArchGDAL
    true
catch
    false
end

const HAS_JSON3 = try
    using JSON3
    true
catch
    false
end

const HAS_CSV = try
    using CSV
    using DataFrames
    true
catch
    false
end

# =============================================================================
# Scaling Configurations (matching Python)
# =============================================================================

const MATRIX_SCALES = Dict("k1" => 500, "k2" => 1000, "k3" => 2000, "k4" => 3000)
const MATRIX_SCALES_QUICK = Dict("k1" => 250, "k2" => 500, "k3" => 750, "k4" => 1000)

const IO_SCALES = Dict("small" => 100_000, "medium" => 500_000, "large" => 1_000_000, "xlarge" => 3_000_000)
const IO_SCALES_QUICK = Dict("small" => 25_000, "medium" => 50_000, "large" => 100_000, "xlarge" => 250_000)

const HYPERSPECTRAL_SCALES = Dict("small" => 128, "medium" => 256, "large" => 512, "xlarge" => 768)
const HYPERSPECTRAL_SCALES_QUICK = Dict("small" => 64, "medium" => 128, "large" => 256, "xlarge" => 384)

const VECTOR_SCALES = Dict("small" => 100_000, "medium" => 500_000, "large" => 1_000_000, "xlarge" => 3_000_000)
const VECTOR_SCALES_QUICK = Dict("small" => 25_000, "medium" => 50_000, "large" => 100_000, "xlarge" => 250_000)

const IDW_SCALES = Dict("small" => 5_000, "medium" => 20_000, "large" => 50_000, "xlarge" => 100_000)
const IDW_SCALES_QUICK = Dict("small" => 2_000, "medium" => 5_000, "large" => 10_000, "xlarge" => 20_000)

const TIMESERIES_SCALES = Dict("small" => 256, "medium" => 512, "large" => 768, "xlarge" => 1024)
const TIMESERIES_SCALES_QUICK = Dict("small" => 128, "medium" => 256, "large" => 512, "xlarge" => 768)

const RASTER_SCALES = Dict("small" => 256, "medium" => 512, "large" => 1024, "xlarge" => 2048)
const RASTER_SCALES_QUICK = Dict("small" => 128, "medium" => 256, "large" => 512, "xlarge" => 768)

const ZONAL_SCALES = Dict("small" => 256, "medium" => 512, "large" => 1024, "xlarge" => 2048)
const ZONAL_SCALES_QUICK = Dict("small" => 128, "medium" => 256, "large" => 512, "xlarge" => 768)

const REPROJ_SCALES = Dict("small" => 1_000, "medium" => 10_000, "large" => 50_000, "xlarge" => 100_000)
const REPROJ_SCALES_QUICK = Dict("small" => 500, "medium" => 2_000, "large" => 5_000, "xlarge" => 10_000)

# =============================================================================
# Benchmark Runner
# =============================================================================

struct BenchmarkResult
    scale_value::Int
    min_time::Float64
    mean_time::Float64
    median_time::Float64
    std_time::Float64
    max_time::Float64
    cv::Float64
    all_times::Vector{Float64}
end

function run_benchmark_at_scale(run_func, n_runs::Int=10)
    times = Float64[]
    for run in 1:n_runs
        GC.gc()
        start_t = time()
        run_func()
        elapsed = time() - start_t
        push!(times, elapsed)
    end
    return times
end

function compute_stats(times::Vector{Float64}, scale_value::Int)
    min_t = minimum(times)
    mean_t = mean(times)
    med_t = median(times)
    std_t = std(times)
    max_t = maximum(times)
    cv = mean_t > 0 ? std_t / mean_t : 0.0
    return BenchmarkResult(scale_value, min_t, mean_t, med_t, std_t, max_t, cv, times)
end

function run_all_scales(name::String, scales::Dict{String,Int}, setup_func, run_func; n_runs::Int=10, unit::String="elements")
    println("\n", "="^70)
    println("SCALING BENCHMARK: $name")
    println("="^70)

    results = Dict{String,Any}()

    sorted_scales = sort(collect(scales), by=x->x[2])

    for (scale_name, scale_value) in sorted_scales
        println("\n[$(scale_name)] Scale: $(scale_value) $(unit)")

        setup_result = setup_func(scale_value)
        times = run_benchmark_at_scale(() -> run_func(setup_result), n_runs)
        stats = compute_stats(times, scale_value)

        results[scale_name] = Dict(
            "scale_value" => scale_value,
            "min" => stats.min_time,
            "mean" => stats.mean_time,
            "median" => stats.median_time,
            "std" => stats.std_time,
            "max" => stats.max_time,
            "cv" => stats.cv,
            "all_times" => stats.all_times
        )

        @printf("  Min: %.4fs (PRIMARY)  |  Mean: %.4fs ± %.4fs  |  CV: %.2f%%\n",
                stats.min_time, stats.mean_time, stats.std_time, stats.cv * 100)
    end

    return results
end

function analyze_complexity(name::String, scales::Dict{String,Int}, results::Dict{String,Any})
    println("\n", "="^70)
    println("COMPLEXITY ANALYSIS: $name")
    println("="^70)

    sorted_names = [s[1] for s in sort(collect(scales), by=x->x[2])]
    if length(sorted_names) < 2
        println("  Insufficient scales for complexity analysis")
        return Dict("k" => nothing, "r_squared" => nothing, "complexity" => "Insufficient data")
    end

    min_times = [results[s]["min"] for s in sorted_names]
    scale_values = [results[s]["scale_value"] for s in sorted_names]

    log_times = log.(min_times)
    log_sizes = log.(scale_values)

    # Manual linear regression: y = k*x + c
    n = length(log_times)
    x_mean = mean(log_sizes)
    y_mean = mean(log_times)

    ss_xx = sum((x .- x_mean).^2 for x in log_sizes)
    ss_xy = sum((log_sizes[i] - x_mean) * (log_times[i] - y_mean) for i in 1:n)

    k = ss_xy / ss_xx
    c = y_mean - k * x_mean

    y_pred = k .* log_sizes .+ c
    ss_res = sum((log_times[i] - y_pred[i])^2 for i in 1:n)
    ss_tot = sum((log_times[i] - y_mean)^2 for i in 1:n)
    r_squared = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0

    # Classify complexity
    if r_squared < 0.7
        complexity_label = "Uncertain (R² < 0.7)"
    elseif k < 1.1
        complexity_label = "O(n) — Linear"
    elseif k < 1.5
        complexity_label = "O(n log n) — Linearithmic"
    elseif k < 2.2
        complexity_label = "O(n²) — Quadratic"
    elseif k < 2.5
        complexity_label = "O(n^2.37) — Matrix multiplication"
    elseif k < 3.5
        complexity_label = "O(n³) — Cubic"
    else
        complexity_label = "> O(n³) — Super-cubic (k=$(round(k, digits=2)))"
    end

    @printf("\n  Log-Log Regression:\n")
    @printf("    Scaling exponent (k): %.3f\n", k)
    @printf("    Intercept (c):        %.3f\n", c)
    @printf("    R²:                   %.4f\n", r_squared)
    @printf("    Estimated complexity: %s\n", complexity_label)

    println("\n  Pairwise scaling ratios:")
    for i in 1:(length(sorted_names)-1)
        size_ratio = scale_values[i+1] / scale_values[i]
        time_ratio = min_times[i+1] / min_times[i]
        exp_est = size_ratio > 1 ? log(time_ratio) / log(size_ratio) : 0.0
        @printf("    %8s -> %8s:  size = %.1fx,  time = %.2fx,  exp ≈ %.2f\n",
                sorted_names[i], sorted_names[i+1], size_ratio, time_ratio, exp_est)
    end

    return Dict(
        "scaling_exponent" => round(k, digits=4),
        "intercept" => round(c, digits=4),
        "r_squared" => round(r_squared, digits=4),
        "complexity_label" => complexity_label
    )
end

function save_results(name::String, scales::Dict{String,Int}, results::Dict{String,Any}, unit::String, n_runs::Int, output_dir=nothing)
    if output_dir === nothing
        output_dir = joinpath(@__DIR__, "results", "scaling")
    end

    complexity = analyze_complexity(name, scales, results)

    output = Dict(
        "benchmark" => name,
        "language" => "julia",
        "unit" => unit,
        "scales" => scales,
        "n_runs" => n_runs,
        "methodology" => "Chen & Revels (2016): minimum time as primary estimator",
        "complexity_analysis" => complexity,
        "results" => results
    )

    mkpath(output_dir)
    output_file = joinpath(output_dir, "$(name)_scaling_julia.json")
    open(output_file, "w") do io
        JSON3.pretty(io, JSON3.write(output), JSON3.AlignmentContext(; indent=2))
    end

    println("\n  Results saved: $output_file")
    return output_file
end

# =============================================================================
# Scenario 1: Matrix Operations Scaling
# =============================================================================

function matrix_setup(n::Int)
    rng = MersenneTwister(42)
    return randn(rng, n, n)
end

function matrix_crossproduct_run(A::Matrix{Float64})
    B = A' * A
    return nothing
end

function matrix_determinant_run(A::Matrix{Float64})
    d = det(A)
    return d
end

function matrix_power_run(A::Matrix{Float64})
    B = abs.(A) ./ 2.0
    C = B .^ 10
    return nothing
end

function benchmark_matrix_scaling(quick::Bool=false)
    scales = quick ? MATRIX_SCALES_QUICK : MATRIX_SCALES

    # Cross-product
    results_xp = run_all_scales("matrix_crossproduct", scales, matrix_setup, matrix_crossproduct_run; n_runs=10, unit="matrix dimension (n)")
    save_results("matrix_crossproduct", scales, results_xp, "matrix dimension (n)", 10)

    # Determinant
    results_det = run_all_scales("matrix_determinant", scales, matrix_setup, matrix_determinant_run; n_runs=10, unit="matrix dimension (n)")
    save_results("matrix_determinant", scales, results_det, "matrix dimension (n)", 10)

    # Matrix power
    results_pow = run_all_scales("matrix_power", scales, matrix_setup, matrix_power_run; n_runs=10, unit="matrix dimension (n)")
    save_results("matrix_power", scales, results_pow, "matrix dimension (n)", 10)
end

# =============================================================================
# Scenario 2: I/O Operations Scaling
# =============================================================================

function io_setup_csv(n::Int)
    rng = MersenneTwister(42)
    lat = rand(rng, n) .* 180 .- 90
    lon = rand(rng, n) .* 360 .- 180
    device_id = rand(rng, 1:10000, n)
    return (lat=lat, lon=lon, device_id=device_id)
end

function io_csv_write_run(data)
    df = DataFrame(lat=data.lat, lon=data.lon, device_id=data.device_id)
    output_path = joinpath(@__DIR__, "data", "io_test_julia.csv")
    mkpath(dirname(output_path))
    CSV.write(output_path, df)
    return nothing
end

function io_setup_binary(n::Int)
    rng = MersenneTwister(42)
    return randn(rng, Float64, n)
end

function io_binary_write_run(arr::Vector{Float64})
    output_path = joinpath(@__DIR__, "data", "io_test_julia.bin")
    mkpath(dirname(output_path))
    open(output_path, "w") do io
        write(io, arr)
    end
    return nothing
end

function benchmark_io_scaling(quick::Bool=false)
    if !HAS_CSV
        println("\n  Skipping I/O scaling: CSV/DataFrames not available")
        return
    end

    scales = quick ? IO_SCALES_QUICK : IO_SCALES

    results_csv = run_all_scales("io_csv_write", scales, io_setup_csv, io_csv_write_run; n_runs=5, unit="rows")
    save_results("io_csv_write", scales, results_csv, "rows", 5)

    results_bin = run_all_scales("io_binary_write", scales, io_setup_binary, io_binary_write_run; n_runs=5, unit="values")
    save_results("io_binary_write", scales, results_bin, "values", 5)
end

# =============================================================================
# Scenario 3: Hyperspectral SAM Scaling
# =============================================================================

function hyperspectral_setup(n_pixels::Int)
    rng = MersenneTwister(42)
    n_bands = 224
    data = randn(rng, Float32, n_bands, n_pixels, n_pixels)
    ref = Float32.(collect(LinRange(0.1, 0.9, n_bands)))
    ref = ref ./ norm(ref)
    return (data=data, ref=ref)
end

function hyperspectral_sam_run(setup)
    data, ref = setup
    n_bands, n_rows, n_cols = size(data)
    chunk_size = 256

    for row in 1:chunk_size:n_rows
        for col in 1:chunk_size:n_cols
            row_end = min(row + chunk_size - 1, n_rows)
            col_end = min(col + chunk_size - 1, n_cols)
            chunk = data[:, row:row_end, col:col_end]
            pixels = reshape(permutedims(chunk, (2, 3, 1)), :, n_bands)

            dot_product = pixels * ref
            pixel_norms = mapslices(x -> norm(x), pixels, dims=2)
            ref_norm = norm(ref)
            cos_angle = dot_product ./ (pixel_norms .* ref_norm .+ 1e-8)
            cos_angle = clamp.(cos_angle, -1.0f0, 1.0f0)
            angles = acos.(cos_angle)
        end
    end
    return nothing
end

function benchmark_hyperspectral_scaling(quick::Bool=false)
    scales = quick ? HYPERSPECTRAL_SCALES_QUICK : HYPERSPECTRAL_SCALES
    results = run_all_scales("hyperspectral_sam", scales, hyperspectral_setup, hyperspectral_sam_run; n_runs=5, unit="pixels per side (n x n x 224 bands)")
    save_results("hyperspectral_sam", scales, results, "pixels per side (n x n x 224 bands)", 5)
end

# =============================================================================
# Scenario 4: Vector Point-in-Polygon Scaling
# =============================================================================

function vector_pip_setup(n_points::Int)
    rng = MersenneTwister(42)
    lon = rand(rng, n_points) .* 360 .- 180
    lat = rand(rng, n_points) .* 180 .- 90
    return (lon=lon, lat=lat)
end

function vector_pip_run(data)
    # Pure Julia implementation: simple rectangular polygon test
    # Tests point containment and haversine distance computation
    lon, lat = data
    n = length(lon)

    # Simulate PIP by checking against a rectangular region
    mask = (lon .> -10.0) .& (lon .< 10.0) .& (lat .> -10.0) .& (lat .< 10.0)

    # Haversine distance for matched points
    lon_m, lat_m = lon[mask], lat[mask]
    distances = zeros(Float64, sum(mask))
    for i in 1:length(distances)
        # Distance to polygon center (0, 0)
        dlon = lon_m[i] - 0.0
        dlat = lat_m[i] - 0.0
        a = sin(dlat/2)^2 + cos(lat_m[i]) * cos(0.0) * sin(dlon/2)^2
        c = 2 * asin(sqrt(a))
        distances[i] = 6371000.0 * c
    end

    return nothing
end

function benchmark_vector_scaling(quick::Bool=false)
    scales = quick ? VECTOR_SCALES_QUICK : VECTOR_SCALES
    results = run_all_scales("vector_pip", scales, vector_pip_setup, vector_pip_run; n_runs=5, unit="query points")
    save_results("vector_pip", scales, results, "query points", 5)
end

# =============================================================================
# Scenario 5: IDW Interpolation Scaling
# =============================================================================

function idw_setup(n_points::Int)
    rng = MersenneTwister(42)
    x = rand(rng, n_points) .* 1000
    y = rand(rng, n_points) .* 1000
    values = 100.0 .* sin.(x ./ 200.0) .* cos.(y ./ 200.0) .+ 50.0 .* sin.(x ./ 50.0) .+ 20.0 .* randn(rng, n_points)

    grid_size = max(100, isqrt(n_points) * 3)
    gx = range(0, 1000, length=grid_size)
    gy = range(0, 1000, length=grid_size)
    grid_x, grid_y = meshgrid(gx, gy)

    return (x=x, y=y, values=values, grid_x=grid_x, grid_y=grid_y, n=n_points, grid_size=grid_size)
end

function meshgrid(x::AbstractRange, y::AbstractRange)
    gx = [xi for xi in x, yi in y]
    gy = [yi for xi in x, yi in y]
    return gx, gy
end

function idw_run(setup)
    x, y, values, grid_x, grid_y, n, grid_size = setup
    k_nearest = min(8, n)
    result = zeros(Float64, grid_size, grid_size)

    # Use brute-force kNN (no KD-tree for simplicity, matches Python behavior)
    for gi in 1:grid_size, gj in 1:grid_size
        gx, gy = grid_x[gi, gj], grid_y[gi, gj]
        dists = sqrt.((x .- gx).^2 .+ (y .- gy).^2)
        dists[dists .< 1e-10] .= 1e-10
        weights = 1.0 ./ dists
        result[gi, gj] = sum(weights .* values) / sum(weights)
    end

    return nothing
end

function benchmark_idw_scaling(quick::Bool=false)
    scales = quick ? IDW_SCALES_QUICK : IDW_SCALES
    results = run_all_scales("idw_interpolation", scales, idw_setup, idw_run; n_runs=3, unit="input points")
    save_results("idw_interpolation", scales, results, "input points", 3)
end

# =============================================================================
# Scenario 6: Time-Series NDVI Scaling
# =============================================================================

function timeseries_setup(n::Int)
    rng = MersenneTwister(42)
    n_dates = 46
    ndvi_stack = randn(rng, Float32, n_dates, n, n) .* 0.2f0 .+ 0.3f0
    return (ndvi_stack=ndvi_stack, n_dates=n_dates)
end

function timeseries_ndvi_run(setup)
    ndvi_stack, n_dates = setup

    # Mean NDVI per date
    mean_ndvi = mean(ndvi_stack, dims=(2, 3))

    # Per-pixel statistics
    mean_px = dropdims(mean(ndvi_stack, dims=1), dims=1)
    max_px = dropdims(maximum(ndvi_stack, dims=1), dims=1)
    min_px = dropdims(minimum(ndvi_stack, dims=1), dims=1)
    std_px = dropdims(std(ndvi_stack, dims=1), dims=1)

    # Amplitude (max - min)
    amplitude = max_px .- min_px

    return nothing
end

function benchmark_timeseries_scaling(quick::Bool=false)
    scales = quick ? TIMESERIES_SCALES_QUICK : TIMESERIES_SCALES
    results = run_all_scales("timeseries_ndvi", scales, timeseries_setup, timeseries_ndvi_run; n_runs=5, unit="pixels per side (n x n x 46 dates)")
    save_results("timeseries_ndvi", scales, results, "pixels per side (n x n x 46 dates)", 5)
end

# =============================================================================
# Scenario 7: Raster Algebra Scaling
# =============================================================================

function raster_setup(n::Int)
    rng = MersenneTwister(42)
    red = rand(rng, Float32, n, n) .* 0.3f0
    nir = rand(rng, Float32, n, n) .* 0.5f0 .+ 0.2f0
    green = rand(rng, Float32, n, n) .* 0.25f0 .+ 0.1f0
    swir = rand(rng, Float32, n, n) .* 0.4f0
    return (red=red, nir=nir, green=green, swir=swir)
end

function raster_algebra_run(setup)
    red, nir, green, swir = setup

    # NDVI
    ndvi = (nir .- red) ./ (nir .+ red .+ 1.0f-8)

    # EVI
    evi = 2.5f0 .* (nir .- red) ./ (nir .+ 6.0f0 .* red .- 7.5f0 .* green .+ 1.0f0)

    # NDWI
    ndwi = (nir .- swir) ./ (nir .+ swir .+ 1.0f-8)

    # 3x3 convolution (mean filter on NDVI)
    kernel = ones(Float32, 3, 3) ./ 9.0f0
    conv = imfilter_mean(ndvi, kernel)

    return nothing
end

function imfilter_mean(arr::AbstractMatrix, kernel::AbstractMatrix)
    # Simple mean filter implementation
    rows, cols = size(arr)
    kr, kc = size(kernel)
    half_r, half_c = kr ÷ 2, kc ÷ 2
    result = similar(arr)

    for r in 1+half_r:rows-half_r, c in 1+half_c:cols-half_c
        patch = arr[r-half_r:r+half_r, c-half_c:c+half_c]
        result[r, c] = sum(patch .* kernel)
    end

    # Pad edges
    result[1:half_r, :] .= 0.0f0
    result[end-half_r+1:end, :] .= 0.0f0
    result[:, 1:half_c] .= 0.0f0
    result[:, end-half_c+1:end] .= 0.0f0

    return result
end

function benchmark_raster_scaling(quick::Bool=false)
    scales = quick ? RASTER_SCALES_QUICK : RASTER_SCALES
    results = run_all_scales("raster_algebra", scales, raster_setup, raster_algebra_run; n_runs=5, unit="pixels per side (n x n)")
    save_results("raster_algebra", scales, results, "pixels per side (n x n)", 5)
end

# =============================================================================
# Scenario 8: Zonal Statistics Scaling
# =============================================================================

function zonal_setup(n::Int)
    rng = MersenneTwister(42)
    raster = randn(rng, Float32, n, n) .* 10.0f0 .+ 50.0f0
    mask = zeros(Int32, n, n)

    # Create 10 rectangular zones
    n_zones = 10
    for z in 1:n_zones
        r0 = div((z-1) * n, n_zones) + 1
        r1 = min(div(z * n, n_zones), n)
        mask[r0:r1, :] .= Int32(z)
    end

    return (raster=raster, mask=mask, n_zones=n_zones)
end

function zonal_stats_run(setup)
    raster, mask, n_zones = setup
    results = []

    for z in 1:n_zones
        zone_mask = mask .== z
        if !any(zone_mask)
            continue
        end
        vals = raster[zone_mask]
        push!(results, Dict("zone" => z, "mean" => mean(vals), "std" => std(vals)))
    end

    return nothing
end

function benchmark_zonal_scaling(quick::Bool=false)
    scales = quick ? ZONAL_SCALES_QUICK : ZONAL_SCALES
    results = run_all_scales("zonal_stats", scales, zonal_setup, zonal_stats_run; n_runs=5, unit="pixels per side (n x n)")
    save_results("zonal_stats", scales, results, "pixels per side (n x n)", 5)
end

# =============================================================================
# Scenario 9: Coordinate Reprojection Scaling
# =============================================================================

function reproj_setup(n::Int)
    rng = MersenneTwister(42)
    lons = rand(rng, n) .* 360.0 .- 180.0
    lats = rand(rng, n) .* 180.0 .- 90.0
    return (lons=lons, lats=lats)
end

function reproj_wgs84_to_utm(lons::Vector{Float64}, lats::Vector{Float64})
    # Approximate UTM conversion using basic formulas
    n = length(lons)
    x = zeros(Float64, n)
    y = zeros(Float64, n)

    for i in 1:n
        lon, lat = lons[i], lats[i]
        zone = Int(floor((lon + 180.0) / 6.0)) + 1
        lon0 = -183.0 + zone * 6.0
        lat_rad = deg2rad(lat)
        lon_rad = deg2rad(lon)
        lon0_rad = deg2rad(lon0)

        # Simplified Transverse Mercator approximation
        k0 = 0.9996
        a = 6378137.0
        e2 = 0.00669438
        e4 = e2^2
        e6 = e2^3

        m = a * ((1 - e2/4 - 3*e4/64 - 5*e6/256) * lat_rad
               - (3*e2/8 + 3*e4/32 + 45*e6/1024) * sin(2*lat_rad)
               + (15*e4/256 + 45*e6/1024) * sin(4*lat_rad)
               - (35*e6/3072) * sin(6*lat_rad))

        n_val = a / sqrt(1 - e2 * sin(lat_rad)^2)
        t = tan(lat_rad)^2
        c = e2 / (1 - e2) * cos(lat_rad)^2
        a_val = cos(lat_rad) * (lon_rad - lon0_rad)

        x[i] = k0 * n_val * (a_val + (1-t+c)*a_val^3/6 + (5-18*t+t^2+72*c-58*0.00669438/(1-0.00669438))*a_val^5/120) + 500000
        y[i] = k0 * (m + n_val * tan(lat_rad) * (a_val^2/2 + (5-t+9*c+4*c^2)*a_val^4/24 + (61-58*t+t^2+600*c-330*0.00669438/(1-0.00669438))*a_val^6/720))
    end

    return (x=x, y=y)
end

function reproj_run(setup)
    lons, lats = setup
    result = reproj_wgs84_to_utm(lons, lats)
    return nothing
end

function benchmark_reproj_scaling(quick::Bool=false)
    scales = quick ? REPROJ_SCALES_QUICK : REPROJ_SCALES
    results = run_all_scales("reprojection", scales, reproj_setup, reproj_run; n_runs=5, unit="points")
    save_results("reprojection", scales, results, "points", 5)
end

# =============================================================================
# Main
# =============================================================================

function main()
    quick = "--quick" in ARGS

    println("="^70)
    println("JULIA — Data Scaling Benchmark Suite")
    println("="^70)
    println("Methodology: $(quick ? "QUICK" : "Full") scaling across all 9 scenarios")
    println("Primary metric: Minimum time (Chen & Revels 2016)")
    println("$(quick ? "Quick mode: smaller scales for faster iteration" : "")")

    # Scenario 1: Matrix Operations
    benchmark_matrix_scaling(quick)

    # Scenario 2: I/O Operations
    benchmark_io_scaling(quick)

    # Scenario 3: Hyperspectral SAM
    benchmark_hyperspectral_scaling(quick)

    # Scenario 4: Vector Point-in-Polygon
    benchmark_vector_scaling(quick)

    # Scenario 5: IDW Interpolation
    benchmark_idw_scaling(quick)

    # Scenario 6: Time-Series NDVI
    benchmark_timeseries_scaling(quick)

    # Scenario 7: Raster Algebra
    benchmark_raster_scaling(quick)

    # Scenario 8: Zonal Statistics
    benchmark_zonal_scaling(quick)

    # Scenario 9: Coordinate Reprojection
    benchmark_reproj_scaling(quick)

    println("\n", "="^70)
    println("All scaling benchmarks complete!")
    println("Results saved to: results/scaling/")
    println("="^70)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
