#!/bin/bash
################################################################################
# GitHub Codespaces Benchmark Setup Script
# Run this after the Codespace is created to download all data
################################################################################

set -e

echo "=============================================="
echo "Codespaces Benchmark Data Downloader"
echo "=============================================="
echo ""

# Check if we're in a codespace
if [ ! -d "/workspaces" ]; then
    echo "⚠️  This script is designed for GitHub Codespaces"
    echo "   Running in local environment..."
fi

# Create directories
echo "Creating directories..."
mkdir -p data results validation results/figures

# Download/generate all benchmark datasets
echo ""
echo "=============================================="
echo "Downloading benchmark datasets..."
echo "=============================================="

cd /workspaces/thesis-benchmarks 2>/dev/null || cd "$(dirname "$0")"

python3 tools/download_data.py --all --synthetic

echo ""
echo "=============================================="
echo "Verifying installation..."
echo "=============================================="

# Check Python
if command -v python3 &> /dev/null; then
    echo "✓ Python: $(python3 --version)"
else
    echo "✗ Python not found"
fi

# Check hyperfine
if command -v hyperfine &> /dev/null; then
    echo "✓ hyperfine: $(hyperfine --version | head -1)"
else
    echo "✗ hyperfine not found - benchmarks may not work"
fi

# Check podman
if command -v podman &> /dev/null; then
    echo "✓ podman: $(podman --version)"
else
    echo "✗ podman not found - container mode won't work"
fi

# Check data
echo ""
echo "Data files:"
if [ -f "data/Cuprite.mat" ]; then
    echo "  ✓ Cuprite.mat ($(du -h data/Cuprite.mat | cut -f1))"
fi
if [ -f "data/srtm/srtm_merged.bin" ]; then
    echo "  ✓ SRTM DEM ($(du -h data/srtm/srtm_merged.bin | cut -f1))"
fi
if [ -f "data/natural_earth_countries.gpkg" ]; then
    echo "  ✓ Natural Earth ($(du -h data/natural_earth_countries.gpkg | cut -f1))"
fi

echo ""
echo "=============================================="
echo "Setup complete!"
echo "=============================================="
echo ""
echo "Run benchmarks:"
echo "  Native mode (faster, less reproducible):"
echo "    ./run_benchmarks.sh --native-only"
echo ""
echo "  Container mode (recommended, reproducible):"
echo "    ./run_benchmarks.sh"
echo ""
echo "  Quick validation:"
echo "    python3 validation/thesis_validation.py --all"
echo ""
echo "  Generate visualizations:"
echo "    python3 tools/thesis_viz.py --all"
echo ""
