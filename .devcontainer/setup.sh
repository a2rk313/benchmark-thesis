#!/bin/bash
################################################################################
# GitHub Codespaces Setup Script
################################################################################
# This script runs automatically when the Codespace is created
################################################################################

set -e

echo "🚀 Setting up GIS Benchmarking environment in GitHub Codespaces..."
echo "   Using Fedora containers from GitHub Container Registry (GHCR)"

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

# Download benchmark datasets
echo ""
echo "=============================================="
echo "Downloading benchmark datasets..."
echo "=============================================="
python3 tools/download_data.py --all --synthetic || echo "⚠️  Data download had warnings"

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
echo "💡 Tip: Use native-only mode since containers are pre-built on GitHub Actions"
echo "   Expected runtime: ~1 hour for full suite"
echo ""
