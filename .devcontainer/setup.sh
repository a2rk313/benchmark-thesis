#!/bin/bash
################################################################################
# GitHub Codespaces Setup Script
################################################################################
# This script runs automatically when the Codespace is created
################################################################################

set -e

echo "🚀 Setting up GIS Benchmarking environment in GitHub Codespaces..."

# Get the GitHub repo owner for container registry
GITHUB_OWNER=$(git config user.name || echo "${GITHUB_REPOSITORY_OWNER:-unknown}")
GITHUB_REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo .)")
IMAGE_PREFIX="ghcr.io/${GITHUB_OWNER,,}/thesis"

# Check if we should use GHCR images
USE_GHCR=false
if [[ "${GITHUB_REPOSITORY:-}" == *"thesis"* ]] || [[ -n "${GITHUB_TOKEN:-}" ]]; then
    USE_GHCR=true
    echo "📦 Detected GitHub Codespaces - will use pre-built containers from GHCR"
fi

# Install hyperfine for benchmarking
echo "⚡ Installing hyperfine..."
HYPERFINE_VERSION="1.20.0"
if ! command -v hyperfine &> /dev/null; then
    wget -q "https://github.com/sharkdp/hyperfine/releases/download/v${HYPERFINE_VERSION}/hyperfine_${HYPERFINE_VERSION}_amd64.deb"
    sudo dpkg -i "hyperfine_${HYPERFINE_VERSION}_amd64.deb"
    rm "hyperfine_${HYPERFINE_VERSION}_amd64.deb"
else
    echo "  ✓ hyperfine already installed"
fi

# Make all scripts executable
chmod +x run_benchmarks.sh check_system.sh
chmod +x benchmarks/*.py benchmarks/*.jl benchmarks/*.R
chmod +x tools/*.py
chmod +x validation/*.py
chmod +x .devcontainer/codespaces_setup.sh

# Create necessary directories
mkdir -p data results validation results/figures

# Pull pre-built containers from GHCR if available
if [ "$USE_GHCR" = true ]; then
    echo ""
    echo "=============================================="
    echo "Pulling pre-built containers from GitHub Container Registry..."
    echo "=============================================="
    
    # Login to GHCR
    echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin 2>/dev/null || true
    
    # Pull Ubuntu containers (for Codespaces)
    for lang in python julia r; do
        image="${IMAGE_PREFIX}-${lang}:ubuntu"
        echo "  Pulling $image..."
        docker pull "$image" 2>/dev/null || echo "  ⚠️  Could not pull $image (will use native)"
    done
    
    # Tag for easy reference
    docker tag "${IMAGE_PREFIX}-python:ubuntu" thesis-python:ubuntu 2>/dev/null || true
    docker tag "${IMAGE_PREFIX}-julia:ubuntu" thesis-julia:ubuntu 2>/dev/null || true
    docker tag "${IMAGE_PREFIX}-r:ubuntu" thesis-r:ubuntu 2>/dev/null || true
fi

# Download benchmark datasets
echo ""
echo "=============================================="
echo "Downloading benchmark datasets..."
echo "=============================================="
python3 tools/download_data.py --all --synthetic || echo "⚠️  Data download failed - will use synthetic"

echo ""
echo "✅ Setup complete!"
echo ""
echo "🎯 You're running on GitHub Codespaces (FREE cloud compute)!"
echo ""
echo "System info:"
echo "  CPU cores: $(nproc)"
echo "  Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  Storage: $(df -h / | awk 'NR==2 {print $4}') available"
echo ""
echo "Next steps:"
echo "  1. Review README.md"
echo "  2. Run system check: ./check_system.sh"
echo "  3. Run benchmarks: ./run_benchmarks.sh --native-only"
echo ""
echo "💡 Tip: This Codespace counts toward your 60 free hours/month"
echo "   Expected runtime: ~2 hours for full suite"
echo ""
