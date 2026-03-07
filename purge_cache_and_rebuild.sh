#!/usr/bin/env bash
# =============================================================================
# CACHE PURGE + REBUILD SCRIPT
# Run this if you hit stale cache errors or build failures
#
# USAGE:
#   ./purge_cache_and_rebuild.sh           # Full rebuild (no cache, ~25 min)
#   ./purge_cache_and_rebuild.sh --cached  # Rebuild with cache (~5 min)
#
# WHAT IT DOES:
#   1. Removes ALL old thesis container images
#   2. Prunes dangling/unused build cache  
#   3. Rebuilds all three containers
# =============================================================================
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Parse arguments
USE_CACHE=false
if [[ "${1:-}" == "--cached" ]]; then
    USE_CACHE=true
fi

echo -e "${BLUE}=== Purging stale container cache ===${NC}"

# Remove old images with all possible tags
echo "  Removing old thesis images..."
for tag in \
    thesis-python:3.14 thesis-python:3.13 thesis-python:latest \
    thesis-julia:1.12  thesis-julia:1.11  thesis-julia:latest \
    thesis-r:4.5       thesis-r:latest; do
    if podman image exists "$tag" 2>/dev/null; then
        echo "    Removing $tag..."
        podman rmi -f "$tag" 2>/dev/null || true
    fi
done

# Prune unused images and build cache
echo "  Pruning build cache..."
podman image prune -af 2>/dev/null || true
podman system prune -af  2>/dev/null || true
echo -e "${GREEN}  ✓ Cache cleared${NC}"
echo ""

# Rebuild strategy
if [ "$USE_CACHE" = true ]; then
    echo -e "${BLUE}=== Rebuilding containers (WITH cache) ===${NC}"
    echo -e "${YELLOW}  Using cache for unchanged layers (faster, ~5 minutes)${NC}"
    CACHE_FLAG=""
else
    echo -e "${BLUE}=== Rebuilding containers (NO cache) ===${NC}"
    echo -e "${YELLOW}  Building from scratch (slower, ~25 minutes but guaranteed fresh)${NC}"
    CACHE_FLAG="--no-cache"
fi
echo ""

build() {
    local tag="$1" file="$2"
    echo -e "${GREEN}Building $tag ...${NC}"
    if podman build $CACHE_FLAG -t "$tag" -f "$file" .; then
        echo -e "${GREEN}  ✓ $tag built successfully${NC}"
    else
        echo -e "${RED}  ❌ $tag FAILED${NC}"
        echo "     Check Containerfile: $file"
        echo ""
        echo "  Troubleshooting:"
        echo "    1. Check TROUBLESHOOTING.md for common errors"
        echo "    2. Try with --cached flag: ./purge_cache_and_rebuild.sh --cached"
        echo "    3. Check system resources: df -h (disk) and free -h (RAM)"
        exit 1
    fi
    echo ""
}

build "thesis-python:3.13" "containers/python.Containerfile"
build "thesis-julia:1.11"  "containers/julia.Containerfile"
build "thesis-r:4.5"       "containers/r.Containerfile"

echo -e "${GREEN}=== All containers rebuilt successfully ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Run benchmarks:  ./run_benchmarks.sh"
echo "  2. Or test manually:"
echo "       podman run --rm thesis-python:3.13 python3 -c 'import scipy; print(\"OK\")'"
echo "       podman run --rm thesis-julia:1.11 julia -e 'using ArchGDAL; println(\"OK\")'"
echo "       podman run --rm thesis-r:4.5 Rscript -e 'library(terra); cat(\"OK\\n\")'"
echo ""

if [ "$USE_CACHE" = false ]; then
    echo -e "${YELLOW}TIP: For faster rebuilds in the future, use: $0 --cached${NC}"
    echo -e "${YELLOW}     (Only do full --no-cache rebuild when debugging build failures)${NC}"
fi
