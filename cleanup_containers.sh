#!/bin/bash
# =============================================================================
# Container Cleanup Script
# Removes dangling images and old containers
# =============================================================================

set -e

echo "========================================================================"
echo "Container Cleanup Tool"
echo "========================================================================"
echo ""

# Function to format size
format_size() {
    local size_kb=$1
    if [ $size_kb -gt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size_kb/1048576}") GB"
    elif [ $size_kb -gt 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size_kb/1024}") MB"
    else
        echo "${size_kb} KB"
    fi
}

# Get current disk usage
echo "[1/4] Current disk usage..."
podman system df

echo ""
echo "[2/4] Removing dangling images (<none>)..."
DANGLING=$(podman images -f "dangling=true" -q)
if [ -n "$DANGLING" ]; then
    COUNT=$(echo "$DANGLING" | wc -l)
    echo "  Found $COUNT dangling image(s)"
    podman rmi $DANGLING || true
    echo "  ✓ Removed dangling images"
else
    echo "  No dangling images found"
fi

echo ""
echo "[3/4] Removing stopped containers..."
STOPPED=$(podman ps -a -f "status=exited" -q)
if [ -n "$STOPPED" ]; then
    COUNT=$(echo "$STOPPED" | wc -l)
    echo "  Found $COUNT stopped container(s)"
    podman rm $STOPPED || true
    echo "  ✓ Removed stopped containers"
else
    echo "  No stopped containers found"
fi

echo ""
echo "[4/4] Pruning system (build cache, unused networks, etc.)..."
podman system prune -f

echo ""
echo "========================================================================"
echo "Cleanup Complete!"
echo "========================================================================"
echo ""
echo "Current images:"
podman images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

echo ""
echo "Disk usage after cleanup:"
podman system df

echo ""
echo "✓ Cleanup finished"
echo ""
echo "To reclaim even more space:"
echo "  podman system prune -a -f --volumes  # Remove ALL unused images"
echo ""
