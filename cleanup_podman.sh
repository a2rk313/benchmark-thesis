#!/bin/bash
# =============================================================================
# Podman Image Cleanup Script
# Removes dangling images and unused containers
# =============================================================================

set -e

echo "=========================================================================="
echo "Podman Image Cleanup"
echo "=========================================================================="
echo ""

# Show current images
echo "Current images:"
podman images | grep -E "REPOSITORY|thesis|<none>" | head -20
echo ""

# Count dangling images
DANGLING_COUNT=$(podman images -f "dangling=true" -q | wc -l)
echo "Found ${DANGLING_COUNT} dangling images (<none>)"
echo ""

if [ "$DANGLING_COUNT" -eq 0 ]; then
    echo "✓ No dangling images to clean"
    echo ""
else
    read -p "Remove all dangling images? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing dangling images..."
        podman image prune -f
        echo "✓ Dangling images removed"
        echo ""
    else
        echo "Skipped dangling image cleanup"
        echo ""
    fi
fi

# Check for old thesis images
echo "Thesis container images:"
podman images | grep thesis || echo "(none found)"
echo ""

# Offer to remove old thesis images
read -p "Remove OLD thesis images (keep only latest)? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing old thesis images..."
    
    # Keep latest, remove older ones
    for img in thesis-python thesis-julia thesis-r; do
        # Get all image IDs for this name
        OLD_IDS=$(podman images --format "{{.ID}}" --filter "reference=${img}" | tail -n +2)
        
        if [ -n "$OLD_IDS" ]; then
            echo "  Removing old ${img} images..."
            echo "$OLD_IDS" | xargs -r podman rmi -f
        fi
    done
    
    echo "✓ Old thesis images removed"
    echo ""
else
    echo "Skipped old image cleanup"
    echo ""
fi

# Clean up stopped containers
STOPPED_COUNT=$(podman ps -a -f "status=exited" -q | wc -l)

if [ "$STOPPED_COUNT" -gt 0 ]; then
    echo "Found ${STOPPED_COUNT} stopped containers"
    read -p "Remove stopped containers? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing stopped containers..."
        podman container prune -f
        echo "✓ Stopped containers removed"
        echo ""
    fi
fi

# Full system prune option
echo ""
echo "Advanced cleanup options:"
echo "  1. Remove ALL unused images (not just dangling)"
echo "  2. Full system prune (containers, images, volumes, networks)"
echo "  3. Skip advanced cleanup"
echo ""
read -p "Choose (1/2/3): " -n 1 -r
echo

case $REPLY in
    1)
        echo "Removing all unused images..."
        podman image prune -a -f
        echo "✓ All unused images removed"
        ;;
    2)
        echo "Running full system prune..."
        podman system prune -a -f --volumes
        echo "✓ Full system prune complete"
        ;;
    3)
        echo "Skipped advanced cleanup"
        ;;
    *)
        echo "Invalid choice, skipped"
        ;;
esac

echo ""
echo "=========================================================================="
echo "Cleanup Complete"
echo "=========================================================================="
echo ""

# Show final state
echo "Remaining images:"
podman images | grep -E "REPOSITORY|thesis|<none>" | head -20

echo ""
echo "Disk space freed:"
podman system df

echo ""
echo "✓ Cleanup finished"
