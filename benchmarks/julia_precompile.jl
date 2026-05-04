#!/usr/bin/env julia
"""
Precompile all Julia packages used in benchmarks.
Run this once before benchmarking to eliminate JIT overhead.
"""

using Pkg

# List of required packages
packages = [
    "CSV",
    "DataFrames",
    "MAT",
    "GeoDataFrames",
    "NearestNeighbors",
    "Statistics",
    "LinearAlgebra",
]

println("Precompiling Julia packages...")
for pkg in packages
    try
        @eval using $(Symbol(pkg))
        println("  ✓ $pkg")
    catch e
        println("  ✗ $pkg: $e")
    end
end

println("\nPrecompilation complete!")

# Warmup common functions
println("\nWarming up common functions...")
function warmup_benchmark()
    # Matrix operations
    A = rand(100, 100)
    B = rand(100, 100)
    C = A * B
    
    # Statistics
    x = rand(1000)
    m = mean(x)
    s = std(x)
    
    return m, s
end

for i in 1:3
    warmup_benchmark()
end

println("Warmup complete!")
