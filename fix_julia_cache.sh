#!/bin/bash
# =============================================================================
# FIX CORRUPTED BUILD CACHE
# Only clears the build cache, keeps your built images safe
# =============================================================================

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== Fixing corrupted build cache ===${NC}"

# Check if julia container exists
if podman image exists "thesis-julia:1.11" 2>/dev/null; then
    echo -e "${GREEN}✓ Found existing thesis-julia image${NC}"
    echo "  This image is safe and will NOT be deleted."
fi

echo ""
echo "Clearing ONLY the build cache (leaves built images intact)..."

# Clear the build cache only (not the images)
podman builder prune --all --force 2>/dev/null || true

echo -e "${GREEN}✓ Build cache cleared${NC}"
echo ""
echo "Now rebuilding julia container..."
echo "  This will take ~15-25 minutes but uses clean cache."
echo ""

# Rebuild just julia
podman build --no-cache -t thesis-julia:1.11 -f containers/julia.Containerfile .

echo ""
echo -e "${GREEN}✓ Done! Your other containers are untouched.${NC}"
