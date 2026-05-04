#!/bin/bash
# setup-benchmarks.sh - First-boot setup for benchmark environment
# Run AFTER manually cloning the thesis-benchmarks repository
set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[0;34m[$(date +'%H:%M:%S')]\033[0m $1"; }
success() { echo -e "\033[0;32m✓ $1\033[0m"; }

log "Import Environment Variables"
source /etc/environment

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

# --- THE BARE-METAL OVERRIDE ---
# Overwrite the global /etc/environment path for this session.
# This forces Julia to WRITE to your local folder, bypassing the root-owned /var/lib/julia,
# while still READING hermetic packages from /usr/share/julia/depot
export JULIA_DEPOT_PATH="$BENCHMARK_DIR/.julia:/usr/share/julia/depot"

# Explicit PROJ artifact pathing
export PROJ_DATA="/usr/share/julia/depot/artifacts/3a09b7a113789836af0106fa82e16f7b97bf806b/share/proj"
export PROJ_LIB="/usr/share/julia/depot/artifacts/3a09b7a113789836af0106fa82e16f7b97bf806b/share/proj"
# -------------------------------

julia --project="$BENCHMARK_DIR" -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"
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
