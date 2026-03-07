#!/usr/bin/env julia
"""
===============================================================================
SCENARIO A.2: Hyperspectral SAM – Julia Implementation (Cuprite dataset)
===============================================================================
"""

using MAT
using Statistics
using LinearAlgebra
using SHA
using JSON3
using Random

function spectral_angle_mapper(pixel_spectra::Matrix{Float32}, reference_spectrum::Vector{Float32})
    epsilon = Float32(1e-8)
    dot_products = pixel_spectra * reference_spectrum
    pixel_norms = [norm(pixel_spectra[i, :]) for i in 1:size(pixel_spectra, 1)]
    ref_norm = norm(reference_spectrum)
    cos_angles = dot_products ./ (pixel_norms .* ref_norm .+ epsilon)
    cos_angles = clamp.(cos_angles, -1.0f0, 1.0f0)
    angles = acos.(cos_angles)
    return angles
end

function main()
    println("=" ^ 70)
    println("JULIA - Scenario A.2: Hyperspectral SAM (Cuprite)")
    println("=" ^ 70)

    # -------------------------------------------------------------------------
    # 1. Load Cuprite dataset
    # -------------------------------------------------------------------------
    println("\n[1/5] Loading Cuprite dataset...")
    vars = matread("data/Cuprite.mat")
    # Find the first non-metadata key
    keys_list = collect(keys(vars))
    data_key = filter(k -> !startswith(string(k), "__"), keys_list)[1]
    data_raw = vars[data_key]  # raw array
    println("  Raw size: ", size(data_raw))

    # Determine which dimension corresponds to bands (should be 224)
    dims = size(data_raw)
    band_dim = findfirst(==(224), dims)
    if band_dim === nothing
        error("Could not find dimension with size 224 (bands). Found sizes: $dims")
    end

    # Permute so that bands become the first dimension
    if band_dim == 1
        data = data_raw
    elseif band_dim == 2
        data = permutedims(data_raw, (2,1,3))
    elseif band_dim == 3
        data = permutedims(data_raw, (3,1,2))
    else
        error("Unexpected number of dimensions")
    end

    n_bands, n_rows, n_cols = size(data)
    println("  ✓ Dataset shape (after reordering): $n_bands bands, $n_rows×$n_cols pixels")

    Random.seed!(42)
    reference_spectrum = rand(Float32, n_bands)
    reference_spectrum ./= norm(reference_spectrum)
    ref_hash = bytes2hex(sha256(reinterpret(UInt8, reference_spectrum)))[1:16]
    println("  ✓ Reference spectrum hash: $ref_hash")

    # -------------------------------------------------------------------------
    # 2. Process in chunks
    # -------------------------------------------------------------------------
    println("\n[2/5] Processing hyperspectral data (chunked)...")
    chunk_size = 256
    sam_results = Float32[]
    pixels_processed = 0
    chunks_processed = 0

    for r_start in 1:chunk_size:n_rows
        r_end = min(r_start + chunk_size - 1, n_rows)
        for c_start in 1:chunk_size:n_cols
            c_end = min(c_start + chunk_size - 1, n_cols)
            # Extract chunk (bands, rows, cols)
            chunk = data[:, r_start:r_end, c_start:c_end]
            # Reshape to (pixels, bands)
            n_pixels = (r_end - r_start + 1) * (c_end - c_start + 1)
            pixel_spectra = permutedims(reshape(chunk, n_bands, n_pixels), (2, 1))
            pixel_spectra = Float32.(pixel_spectra)

            sam_angles = spectral_angle_mapper(pixel_spectra, reference_spectrum)
            append!(sam_results, sam_angles)
            pixels_processed += n_pixels
            chunks_processed += 1

            if chunks_processed % 10 == 0
                print("\r    Processed $chunks_processed chunks ($pixels_processed pixels)...")
            end
        end
    end
    println("\r    Processed $chunks_processed chunks ($pixels_processed pixels)... Done!")

    # -------------------------------------------------------------------------
    # 3. Statistics
    # -------------------------------------------------------------------------
    println("\n[3/5] Computing statistics...")
    mean_sam = mean(sam_results)
    median_sam = median(sam_results)
    std_sam = std(sam_results)
    min_sam = minimum(sam_results)
    max_sam = maximum(sam_results)
    println("  ✓ Mean SAM: $(round(mean_sam, digits=6)) rad ($(round(rad2deg(mean_sam), digits=2))°)")
    println("  ✓ Median SAM: $(round(median_sam, digits=6)) rad")
    println("  ✓ Std Dev: $(round(std_sam, digits=6)) rad")

    # -------------------------------------------------------------------------
    # 4. Validation
    # -------------------------------------------------------------------------
    println("\n[4/5] Generating validation data...")
    result_str = "$(round(mean_sam, digits=8))_$(pixels_processed)_$(round(median_sam, digits=8))"
    result_hash = bytes2hex(sha256(result_str))[1:16]
    println("  ✓ Validation hash: $result_hash")

    results = Dict(
        "language" => "julia",
        "scenario" => "hyperspectral_sam",
        "pixels_processed" => pixels_processed,
        "chunks_processed" => chunks_processed,
        "n_bands" => n_bands,
        "mean_sam_rad" => mean_sam,
        "median_sam_rad" => median_sam,
        "std_sam_rad" => std_sam,
        "min_sam_rad" => min_sam,
        "max_sam_rad" => max_sam,
        "mean_sam_deg" => rad2deg(mean_sam),
        "validation_hash" => result_hash,
        "reference_hash" => ref_hash
    )

    mkpath("validation")
    open("validation/raster_julia_results.json", "w") do f
        JSON3.write(f, results)
    end
    println("\n  ✓ Results saved to validation/raster_julia_results.json")
    println("=" ^ 70)
    return 0
end

exit(main())
