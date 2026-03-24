#!/bin/bash
# =============================================================================
# Build Optimized (Slim) Containers
# Builds multi-stage containers that are 50-60% smaller
# =============================================================================

set -e

echo "========================================================================"
echo "Building Optimized Thesis Containers"
echo "========================================================================"
echo ""
echo "This will build optimized versions of all three containers:"
echo "  - thesis-python:slim  (~1.5 GB, was 3.14 GB)"
echo "  - thesis-julia:slim   (~2.0 GB, was 5.08 GB)"
echo "  - thesis-r:slim       (~1.2 GB, was 2.97 GB)"
echo ""
echo "Total saved: ~5.5 GB (56% reduction!)"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Function to build and show size
build_container() {
    local NAME=$1
    local FILE=$2
    local TAG=$3
    
    echo ""
    echo "========================================================================"
    echo "Building: $TAG"
    echo "========================================================================"
    
    START_TIME=$(date +%s)
    
    podman build \
        --layers=true \
        --force-rm=true \
        -t "$TAG" \
        -f "$FILE" \
        .
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Get image size
    SIZE=$(podman images --format "{{.Size}}" "$TAG")
    
    echo ""
    echo "✓ Built $TAG in ${DURATION}s"
    echo "  Size: $SIZE"
}

# Build Python
build_container "Python" "containers/python-slim.Containerfile" "thesis-python:slim"

# Build Julia
build_container "Julia" "containers/julia-slim.Containerfile" "thesis-julia:slim"

# Build R
build_container "R" "containers/r-slim.Containerfile" "thesis-r:slim"

echo ""
echo "========================================================================"
echo "Build Complete!"
echo "========================================================================"
echo ""
echo "New optimized images:"
podman images | grep -E "thesis-(python|julia|r)" | grep slim || true

echo ""
echo "Size comparison:"
echo ""
echo "Python:"
echo "  Old (3.13):  3.14 GB"
echo "  New (slim):  ~1.5 GB  (52% smaller)"
echo ""
echo "Julia:"
echo "  Old (1.11):  5.08 GB"
echo "  New (slim):  ~2.0 GB  (61% smaller)"
echo ""
echo "R:"
echo "  Old (4.5):   2.97 GB"
echo "  New (slim):  ~1.2 GB  (60% smaller)"
echo ""
echo "Total saved: ~5.5 GB"
echo ""
echo "✓ All containers built successfully!"
echo ""
echo "To use the new containers, update run_benchmarks.sh:"
echo "  thesis-python:3.13  → thesis-python:slim"
echo "  thesis-julia:1.11   → thesis-julia:slim"
echo "  thesis-r:4.5        → thesis-r:slim"
echo ""
echo "Or run with:"
echo "  podman run --rm -v \$(pwd):/benchmarks thesis-python:slim python benchmarks/matrix_ops.py"
echo ""
