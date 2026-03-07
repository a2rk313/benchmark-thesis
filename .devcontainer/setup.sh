#!/bin/bash
################################################################################
# GitHub Codespaces Setup Script
################################################################################
# This script runs automatically when the Codespace is created
################################################################################

echo "🚀 Setting up GIS Benchmarking environment in GitHub Codespaces..."

# Install podman (Docker alternative, rootless)
echo "📦 Installing podman..."
sudo apt-get update -qq
sudo apt-get install -y -qq podman podman-docker

# Install hyperfine for benchmarking
echo "⚡ Installing hyperfine..."
HYPERFINE_VERSION="1.20.0"
wget -q "https://github.com/sharkdp/hyperfine/releases/download/v${HYPERFINE_VERSION}/hyperfine_${HYPERFINE_VERSION}_amd64.deb"
sudo dpkg -i "hyperfine_${HYPERFINE_VERSION}_amd64.deb"
rm "hyperfine_${HYPERFINE_VERSION}_amd64.deb"

# Make all scripts executable
chmod +x run_benchmarks.sh check_system.sh
chmod +x benchmarks/*.py benchmarks/*.jl benchmarks/*.R
chmod +x tools/*.py
chmod +x validation/*.py

# Create necessary directories
mkdir -p data results validation

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
echo "  3. Run benchmarks: ./run_benchmarks.sh"
echo ""
echo "💡 Tip: This Codespace counts toward your 120 free core-hours/month"
echo "   Expected runtime: ~2 hours (uses ~8 core-hours on 4-core machine)"
echo ""
