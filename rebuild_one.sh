#!/usr/bin/env bash
# =============================================================================
# SELECTIVE CONTAINER REBUILD
# Rebuild just one container, keeping cache for unchanged layers
#
# USAGE:
#   ./rebuild_one.sh python    # Rebuild Python only
#   ./rebuild_one.sh julia     # Rebuild Julia only
#   ./rebuild_one.sh r         # Rebuild R only
#   ./rebuild_one.sh all       # Rebuild all (same as run_benchmarks.sh)
#
# TIME SAVINGS:
#   Full rebuild (all 3):     18 min
#   Single container:         5-8 min
#   With cache (no changes):  10 sec
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

if [ $# -eq 0 ]; then
    echo "Usage: $0 {python|julia|r|all}"
    echo ""
    echo "Examples:"
    echo "  $0 python    # Rebuild Python container only (~5 min)"
    echo "  $0 julia     # Rebuild Julia container only (~8 min)"
    echo "  $0 r         # Rebuild R container only (~5 min)"
    echo "  $0 all       # Rebuild all containers (~18 min)"
    exit 1
fi

CONTAINER=$1

build_container() {
    local name=$1
    local tag=$2
    local file=$3
    
    echo -e "${BLUE}Building $name container...${NC}"
    
    # Remove old image (forces rebuild but uses cache for unchanged layers)
    if podman image exists "$tag" 2>/dev/null; then
        echo "  Removing old image: $tag"
        podman rmi -f "$tag" 2>/dev/null || true
    fi
    
    # Build (uses cache for unchanged layers)
    if podman build -t "$tag" -f "$file" .; then
        echo -e "${GREEN}✓ $name built successfully${NC}"
        
        # Show digest
        local digest
        digest=$(podman image inspect "$tag" --format '{{.Digest}}' 2>/dev/null || echo "unknown")
        echo "  Digest: ${digest:7:16}..."
    else
        echo -e "${RED}✗ $name build failed${NC}"
        echo "  Check Containerfile: $file"
        exit 1
    fi
    echo ""
}

case $CONTAINER in
    python)
        echo -e "${YELLOW}=== Rebuilding Python Container ===${NC}"
        echo "Expected time: ~5 minutes (with cache)"
        echo ""
        build_container "Python" "thesis-python:3.13" "containers/python.Containerfile"
        ;;
        
    julia)
        echo -e "${YELLOW}=== Rebuilding Julia Container ===${NC}"
        echo "Expected time: ~8 minutes (with cache)"
        echo ""
        build_container "Julia" "thesis-julia:1.11" "containers/julia.Containerfile"
        ;;
        
    r)
        echo -e "${YELLOW}=== Rebuilding R Container ===${NC}"
        echo "Expected time: ~5 minutes (with cache)"
        echo ""
        build_container "R" "thesis-r:4.5" "containers/r.Containerfile"
        ;;
        
    all)
        echo -e "${YELLOW}=== Rebuilding All Containers ===${NC}"
        echo "Expected time: ~18 minutes (with cache)"
        echo ""
        build_container "Python" "thesis-python:3.13" "containers/python.Containerfile"
        build_container "Julia" "thesis-julia:1.11" "containers/julia.Containerfile"
        build_container "R" "thesis-r:4.5" "containers/r.Containerfile"
        ;;
        
    *)
        echo -e "${RED}Error: Unknown container '$CONTAINER'${NC}"
        echo "Valid options: python, julia, r, all"
        exit 1
        ;;
esac

echo -e "${GREEN}=== Rebuild Complete ===${NC}"
echo ""
echo "Next steps:"
echo "  Test:  podman run --rm $tag bash -c 'echo OK'"
echo "  Run:   ./run_benchmarks.sh"
