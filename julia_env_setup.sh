# On bootc image, packages live in the system depot
# Do NOT override with local paths
if [ -f /etc/benchmark-bootc-release ]; then
    export JULIA_DEPOT_PATH="/var/lib/julia:/usr/share/julia/depot"
    export JULIA_PKG_OFFLINE="true"
else
    export JULIA_DEPOT_PATH="/var/home/a2rk/Documents/ThesisContainer/thesis-benchmarks/.julia:$HOME/.julia"
    export JULIA_PKG_OFFLINE="false"
fi
export JULIA_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
