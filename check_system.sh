#!/bin/bash
################################################################################
# SYSTEM REQUIREMENTS CHECKER
################################################################################
# Run this before attempting to build containers to verify all dependencies
# are available and identify potential issues early.
################################################################################

echo "========================================================================"
echo "🔍 SYSTEM REQUIREMENTS CHECK"
echo "========================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

# Function to check command
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        if [ -n "$2" ]; then
            VERSION=$($1 $2 2>&1 | head -1)
            echo "  Version: $VERSION"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT installed"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check Python package availability in Fedora repos
check_fedora_package() {
    if dnf list available $1 &> /dev/null || dnf list installed $1 &> /dev/null; then
        VERSION=$(dnf info $1 2>/dev/null | grep "^Version" | awk '{print $3}' | head -1)
        echo -e "${GREEN}✓${NC} $1 is available (version: $VERSION)"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT available in Fedora repos"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check disk space
check_disk_space() {
    AVAILABLE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    REQUIRED=$1
    
    if [ "$AVAILABLE" -gt "$REQUIRED" ]; then
        echo -e "${GREEN}✓${NC} Sufficient disk space: ${AVAILABLE}GB available (need ${REQUIRED}GB)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Low disk space: ${AVAILABLE}GB available (recommended: ${REQUIRED}GB)"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

# Function to check RAM
check_ram() {
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    REQUIRED=$1
    
    if [ "$TOTAL_RAM" -ge "$REQUIRED" ]; then
        echo -e "${GREEN}✓${NC} Sufficient RAM: ${TOTAL_RAM}GB total (need ${REQUIRED}GB)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Low RAM: ${TOTAL_RAM}GB total (recommended: ${REQUIRED}GB)"
        echo "  Note: Hyperspectral benchmarks may fail or run slowly"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

################################################################################
# 1. ESSENTIAL TOOLS
################################################################################
echo -e "${BLUE}[1/6] Checking essential tools...${NC}"
check_command podman "--version"
check_command hyperfine "--version"
check_command git "--version"
echo ""

################################################################################
# 2. FEDORA PACKAGE AVAILABILITY
################################################################################
echo -e "${BLUE}[2/6] Checking Fedora package availability...${NC}"

# Check if Python 3.13 is available (python3 default on Fedora 43)
if ! check_fedora_package python3; then
    echo -e "${YELLOW}  → Suggestion: Use Python 3.13 instead${NC}"
    echo "     Edit containers/python.Containerfile and replace 'python3' with 'python3'"
fi

# Check geospatial libraries
check_fedora_package gdal
check_fedora_package proj
check_fedora_package geos
check_fedora_package sqlite
echo ""

# Check Julia availability
echo -e "${BLUE}Note:${NC} Julia will be downloaded directly (not from Fedora repos)"

################################################################################
# 3. SYSTEM RESOURCES
################################################################################
echo -e "${BLUE}[3/6] Checking system resources...${NC}"
check_disk_space 25
check_ram 8
echo ""

################################################################################
# 4. NETWORK CONNECTIVITY
################################################################################
echo -e "${BLUE}[4/6] Checking network connectivity...${NC}"

# Test connection to key download sources
URLS=(
    "https://julialang-s3.julialang.org"
    "https://naciscdn.org"
    "https://registry.fedoraproject.org"
)

for url in "${URLS[@]}"; do
    if curl -s --head --connect-timeout 5 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Can reach $url"
    else
        echo -e "${YELLOW}⚠${NC} Cannot reach $url"
        echo "  This may cause downloads to fail"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

################################################################################
# 5. CONTAINER RUNTIME
################################################################################
echo -e "${BLUE}[5/6] Checking container runtime configuration...${NC}"

# Check if podman can pull images
if podman pull docker.io/library/fedora:43 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Can pull Fedora 43 base image"
else
    echo -e "${RED}✗${NC} Cannot pull Fedora 43 base image"
    echo "  Check podman configuration and network"
    ERRORS=$((ERRORS + 1))
fi

# Check storage space for containers
PODMAN_ROOT=$(podman info --format='{{.Store.GraphRoot}}' 2>/dev/null || echo "/var/lib/containers")
if [ -d "$PODMAN_ROOT" ]; then
    STORAGE_AVAIL=$(df -BG "$PODMAN_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$STORAGE_AVAIL" -gt 10 ]; then
        echo -e "${GREEN}✓${NC} Container storage: ${STORAGE_AVAIL}GB available"
    else
        echo -e "${YELLOW}⚠${NC} Low container storage: ${STORAGE_AVAIL}GB available (need 10GB+)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi
echo ""

################################################################################
# 6. OPTIONAL FEATURES
################################################################################
echo -e "${BLUE}[6/6] Checking optional features...${NC}"

# Check if perf is available (for CPU profiling)
if check_command perf "--version" 2>/dev/null; then
    :
else
    echo "  Note: CPU profiling will not be available"
fi

# Check if user can drop caches (for cold start benchmarks)
if [ -w /proc/sys/vm/drop_caches ] 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Can clear system caches (cold start benchmarks will be accurate)"
elif sudo -n echo "" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Can use sudo to clear caches"
else
    echo -e "${YELLOW}⚠${NC} Cannot clear system caches"
    echo "  Cold start benchmarks may not be fully accurate"
    echo "  Run with sudo for best results, or accept this limitation"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

################################################################################
# SUMMARY
################################################################################
echo "========================================================================"
echo "SUMMARY"
echo "========================================================================"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "  System is ready to run benchmarks."
    echo ""
    echo "Next step: ./run_benchmarks.sh"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo "  System can run benchmarks, but some features may be limited."
    echo "  Review warnings above and address if needed."
    echo ""
    echo "You can proceed with: ./run_benchmarks.sh"
elif [ $ERRORS -gt 0 ]; then
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    echo "  Critical dependencies are missing."
    echo "  Fix errors above before running benchmarks."
    echo ""
    echo "Common fixes:"
    echo "  - Install podman: sudo dnf install podman"
    echo "  - Install hyperfine: cargo install hyperfine"
    echo "  - Check network connectivity"
    exit 1
fi

echo "========================================================================"

exit 0
