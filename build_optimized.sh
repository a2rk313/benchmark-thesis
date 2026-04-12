#!/bin/bash
# =============================================================================
# Build Ultra-Optimized Thesis Containers
# Uses official slim base images for maximum size/speed optimization
# =============================================================================

set -e

echo "=========================================================================="
echo "Building Ultra-Optimized Thesis Containers"
echo "=========================================================================="
echo ""
echo "Expected sizes:"
echo "  Python: ~400MB (was 3GB) - 87% reduction"
echo "  Julia:  ~600MB (was 3GB) - 80% reduction"
echo "  R:      ~800MB (was 2GB) - 60% reduction"
echo ""
echo "Build time: ~10-20 minutes total"
echo ""

# Check if we're in the right directory
if [ ! -d "containers" ]; then
    echo "❌ Error: containers/ directory not found"
    echo "Please run this script from the thesis-benchmarks root directory"
    exit 1
fi

# Check if optimized Containerfiles exist
if [ ! -f "containers/python-optimized.Containerfile" ]; then
    echo "❌ Error: Optimized Containerfiles not found"
    echo "Please ensure python-optimized.Containerfile, julia-optimized.Containerfile,"
    echo "and r-optimized.Containerfile exist in containers/"
    exit 1
fi

# Function to build with timing
build_container() {
    local name=$1
    local tag=$2
    local file=$3
    
    echo ""
    echo "=========================================================================="
    echo "Building ${name}"
    echo "=========================================================================="
    
    START_TIME=$(date +%s)
    
    if podman build -t "${tag}" -f "${file}" .; then
        END_TIME=$(date +%s)
        BUILD_TIME=$((END_TIME - START_TIME))
        
        # Get image size
        SIZE=$(podman images --format "{{.Size}}" "${tag}")
        
        echo ""
        echo "✓ ${name} built successfully"
        echo "  Tag: ${tag}"
        echo "  Size: ${SIZE}"
        echo "  Build time: ${BUILD_TIME}s"
        echo ""
    else
        echo ""
        echo "❌ ${name} build failed"
        echo ""
        return 1
    fi
}

# Ask user which containers to build
echo "Which containers would you like to build?"
echo "  1. Python only"
echo "  2. Julia only"
echo "  3. R only"
echo "  4. All three (recommended)"
echo ""
read -p "Choose (1/2/3/4): " choice

case $choice in
    1)
        build_container "Python (optimized)" \
                       "thesis-python:3.13-slim" \
                       "containers/python-optimized.Containerfile"
        ;;
    2)
        build_container "Julia (optimized)" \
                       "thesis-julia:1.11-slim" \
                       "containers/julia-optimized.Containerfile"
        ;;
    3)
        build_container "R (optimized)" \
                       "thesis-r:4.5-slim" \
                       "containers/r-optimized.Containerfile"
        ;;
    4)
        echo "Building all three containers..."
        echo ""
        
        # Build Python
        build_container "Python (optimized)" \
                       "thesis-python:3.13-slim" \
                       "containers/python-optimized.Containerfile"
        
        # Build Julia
        build_container "Julia (optimized)" \
                       "thesis-julia:1.11-slim" \
                       "containers/julia-optimized.Containerfile"
        
        # Build R
        build_container "R (optimized)" \
                       "thesis-r:4.5-slim" \
                       "containers/r-optimized.Containerfile"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "=========================================================================="
echo "Build Summary"
echo "=========================================================================="
echo ""

# Show all thesis images
echo "All thesis container images:"
podman images | grep -E "REPOSITORY|thesis"

echo ""
echo "Disk usage:"
podman system df

echo ""
echo "=========================================================================="
echo "✓ Build Complete"
echo "=========================================================================="
echo ""
echo "Old containers are still available:"
echo "  thesis-python:3.13"
echo "  thesis-julia:1.11"
echo "  thesis-r:4.5"
echo ""
echo "New optimized containers:"
echo "  thesis-python:3.13-slim (50-60% smaller!)"
echo "  thesis-julia:1.11-slim (50-60% smaller!)"
echo "  thesis-r:4.5-slim (50-60% smaller!)"
echo ""
echo "To remove old containers, run: ./cleanup_podman.sh"
echo ""
echo "To use optimized containers, update your run scripts to use -slim tags"
echo ""
