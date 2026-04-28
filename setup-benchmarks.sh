#!/bin/bash
# setup-benchmarks.sh - First-boot setup for benchmark environment
# Run AFTER manually cloning the thesis-benchmarks repository
set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[0;34m[$(date +'%H:%M:%S')]\033[0m $1"; }
success() { echo -e "\033[0;32m✓ $1\033[0m"; }

log "Initializing benchmark environment..."

# 1. Create .julia folder
mkdir -p "$BENCHMARK_DIR/.julia"
success "Created .julia directory"

# 2. Download data
if [ -f "$BENCHMARK_DIR/tools/download_data.py" ]; then
    log "Downloading benchmark datasets..."
    python3 "$BENCHMARK_DIR/tools/download_data.py" --all || log "Warning: Data download encountered issues"
    success "Benchmark data ready"
fi

# 3. Precompile Julia packages with relative depot path
source "$(dirname "$0")/julia_env_setup.sh"
log "Precompiling Julia packages..."
julia -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"
success "Julia packages precompiled"

log ""
log "=============================================="
log "Setup complete!"
log "=============================================="
log ""
log "Run benchmarks with:"
log "  ./run_benchmarks.sh              # Full suite (containers + native)"
log "  ./run_benchmarks.sh --native-only   # Native bare-metal only"
log ""