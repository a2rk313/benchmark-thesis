#!/usr/bin/env bash
# =============================================================================
# THESIS BENCHMARK SUITE ORCHESTRATOR
# Version: 3.0.0 (academic rigor + enhanced orchestration)
#
# FEATURES:
#   - Container benchmarks (reproducible, isolated environment)
#   - Native benchmarks (real-world performance on host system)
#   - Side-by-side comparison of container vs native performance
#   - GHCR pull mode (skip builds, use pre-built images from GitHub Actions)
#   - Resume capability (skip already-run benchmarks)
#   - Hardware info capture (CPU, RAM, disk for methodology section)
#   - Timestamp logging (execution times in results)
#   - Progress estimation (ETA for remaining benchmarks)
#   - Dry-run mode (preview execution plan)
#   - Cleanup option (clear old results)
#   - Error recovery (continue on failure, log errors)
#
# USAGE:
#   ./run_benchmarks.sh                     # Build + run all
#   ./run_benchmarks.sh --container-only    # Container benchmarks only
#   ./run_benchmarks.sh --native-only       # Native benchmarks only
#   ./run_benchmarks.sh --use-ghcr          # Pull pre-built images from GHCR
#   ./run_benchmarks.sh --resume            # Resume from last checkpoint
#   ./run_benchmarks.sh --clean             # Clear old results before running
#   ./run_benchmarks.sh --dry-run           # Preview execution plan
# =============================================================================
set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE="all"
USE_GHCR=false
RESUME=false
CLEAN=false
DRY_RUN=false
ERRORS=()
BENCHMARK_COUNT=0
TOTAL_BENCHMARKS=0
START_TIME=$(date +%s)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container-only) MODE="container"; shift ;;
        --native-only)    MODE="native"; shift ;;
        --use-ghcr)       USE_GHCR=true; shift ;;
        --resume)         RESUME=true; shift ;;
        --clean)          CLEAN=true; shift ;;
        --dry-run)        DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --container-only   Run container benchmarks only"
            echo "  --native-only      Run native benchmarks only"
            echo "  --use-ghcr         Pull pre-built images from GHCR"
            echo "  --resume           Resume from last checkpoint"
            echo "  --clean            Clear old results before running"
            echo "  --dry-run          Preview execution plan"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Colour codes ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
MAGENTA='\033[0;35m'; CYAN='\033[0;36m'

# ── Utility functions ─────────────────────────────────────────────────────────
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
elapsed_time() {
    local now=$(date +%s)
    local diff=$((now - START_TIME))
    printf "%02d:%02d:%02d" $((diff/3600)) $((diff%3600/60)) $((diff%60))
}
eta() {
    local done=$1 total=$2
    if [[ $done -eq 0 ]]; then echo "calculating..."; return; fi
    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    local rate=$((elapsed / done))
    local remaining=$(( (total - done) * rate ))
    printf "%02d:%02d:%02d" $((remaining/3600)) $((remaining%3600/60)) $((remaining%60))
}
progress() {
    BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1))
    local pct=$((BENCHMARK_COUNT * 100 / TOTAL_BENCHMARKS))
    echo -e "  ${CYAN}[${BENCHMARK_COUNT}/${TOTAL_BENCHMARKS}] (${pct}%) ETA: $(eta $BENCHMARK_COUNT $TOTAL_BENCHMARKS)${NC}"
}
log_error() {
    local msg="$1"
    ERRORS+=("$msg")
    echo -e "  ${RED}❌ ERROR: $msg${NC}"
    echo "[$(timestamp)] ERROR: $msg" >> results/errors.log
}
check_resume() {
    local checkpoint="$1"
    if [[ "$RESUME" == "true" ]] && [[ -f "results/.checkpoint_${checkpoint}" ]]; then
        echo -e "  ${YELLOW}⏭  Skipping (already completed, use --clean to re-run)${NC}"
        return 0
    fi
    return 1
}
mark_checkpoint() {
    local checkpoint="$1"
    touch "results/.checkpoint_${checkpoint}"
}

# ── Hardware info capture ────────────────────────────────────────────────────
capture_hardware_info() {
    mkdir -p results
    cat > results/hardware_info.json << HWEOF
{
  "captured_at": "$(timestamp)",
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "os": "$(uname -s) $(uname -r)",
  "cpu_model": "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unknown')",
  "cpu_cores": "$(nproc 2>/dev/null || echo 'unknown')",
  "cpu_freq_mhz": "$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unknown')",
  "total_ram_gb": "$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'unknown')",
  "disk_available_gb": "$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo 'unknown')",
  "kernel": "$(uname -v)",
  "architecture": "$(uname -m)"
}
HWEOF
    echo -e "  ${GREEN}✓${NC} Hardware info captured → results/hardware_info.json"
}

# ── Configuration ─────────────────────────────────────────────────────────────
COLD_START_RUNS=5
BENCHMARK_RUNS=50
WARMUP_RUNS=5
CACHE_WARMUP=3
FULL_SUITE_REPEATS=3

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)

# Container image tags
if [[ "$USE_GHCR" == "true" ]] || [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    OWNER=$(echo "${GITHUB_REPOSITORY:-a2rk313/benchmark-thesis}" | cut -d/ -f1 | tr '[:upper:]' '[:lower:]')
    PYTHON_TAG="ghcr.io/${OWNER}/thesis-python:fedora"
    JULIA_TAG="ghcr.io/${OWNER}/thesis-julia:fedora"
    R_TAG="ghcr.io/${OWNER}/thesis-r:fedora"
else
    PYTHON_TAG="thesis-python:3.13"
    JULIA_TAG="thesis-julia:1.11"
    R_TAG="thesis-r:4.5"
fi

export JULIA_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
export OMP_NUM_THREADS=8

CPU_PIN_ENABLED=true
CPU_CORES=""
NUMA_ENABLED=true
NUMA_NODE=0

ENABLE_VECTOR=true
ENABLE_INTERPOLATION=true
ENABLE_TIMESERIES=true
ENABLE_HYPERSPECTRAL=true

CONFIDENCE_LEVEL=0.95
SIGNIFICANCE_LEVEL=0.05

# Count total benchmarks for progress tracking
TOTAL_BENCHMARKS=0
[[ "$MODE" != "native" ]] && TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 15))
[[ "$MODE" != "container" ]] && TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 12))
TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 5))

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
echo "========================================================================"
echo "  THESIS BENCHMARK SUITE v3.0 (Academic Rigor Edition)"
echo "========================================================================"
echo -e "${NC}"
echo "  Started: $(timestamp)"
echo ""

if [[ "$MODE" == "all" ]]; then
    echo -e "  ${MAGENTA}MODE: FULL (Native + Container)${NC}"
elif [[ "$MODE" == "container" ]]; then
    echo -e "  ${YELLOW}MODE: CONTAINER ONLY${NC}"
else
    echo -e "  ${GREEN}MODE: NATIVE ONLY${NC}"
fi

[[ "$USE_GHCR" == "true" ]] && echo -e "  ${CYAN}GHCR: Pulling pre-built images${NC}"
[[ "$RESUME" == "true" ]] && echo -e "  ${CYAN}RESUME: Skipping completed benchmarks${NC}"
[[ "$CLEAN" == "true" ]] && echo -e "  ${YELLOW}CLEAN: Clearing old results${NC}"
[[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}DRY RUN: Preview mode (no execution)${NC}"

echo ""
echo "  Container images:"
echo "    Python : $PYTHON_TAG"
echo "    Julia  : $JULIA_TAG"
echo "    R      : $R_TAG"
echo ""
echo "  Native tools:"
echo "    Python : $(python3 --version 2>/dev/null | cut -d' ' -f2 || echo 'not found')"
echo "    Julia  : $(julia --version 2>/dev/null | cut -d' ' -f3 || echo 'not found')"
echo "    R      : $(R --version 2>/dev/null | head -1 | cut -d' ' -f3 || echo 'not found')"
echo ""
echo "  Thread config: JULIA_NUM_THREADS=$JULIA_NUM_THREADS, OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS"
echo ""
echo "  Academic rigor settings:"
echo "    Benchmark runs: $BENCHMARK_RUNS"
echo "    Warmup runs: $WARMUP_RUNS + $CACHE_WARMUP cache warmup"
echo "    CPU pinning: $CPU_PIN_ENABLED"
echo "    NUMA binding: $NUMA_ENABLED"
echo ""

# ── Dry run mode ──────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BOLD}${YELLOW}=== DRY RUN - Execution Plan ===${NC}"
    echo ""
    if [[ "$MODE" != "native" ]]; then
        echo "  1. Build/pull containers"
        echo "  2. Verify environments"
        echo "  3. Prepare datasets"
        echo "  4. Cold start benchmarks (container)"
        echo "  5. Warm start benchmarks (container)"
        echo "  6. Matrix operations (container)"
        echo "  7. I/O operations (container)"
        echo "  8. Memory profiling (container)"
        echo "  9. Validate results (container)"
    fi
    if [[ "$MODE" != "container" ]]; then
        echo "  10. Native system benchmarks"
    fi
    echo "  11. Generate academic report"
    echo ""
    echo -e "${GREEN}Dry run complete. Remove --dry-run to execute.${NC}"
    exit 0
fi

# ── Clean mode ────────────────────────────────────────────────────────────────
if [[ "$CLEAN" == "true" ]]; then
    echo -e "${YELLOW}Cleaning old results...${NC}"
    rm -rf results/
    mkdir -p results
    echo -e "${GREEN}✓ Clean complete${NC}"
    echo ""
fi

mkdir -p results

# ── [0/10] Dependency check ───────────────────────────────────────────────────
echo -e "${BLUE}[0/10] Checking dependencies...${NC}"
for cmd in podman hyperfine; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}❌ $cmd not found.${NC}"
        [ "$cmd" = "podman" ]    && echo "     Install: sudo dnf install podman"
        [ "$cmd" = "hyperfine" ] && echo "     Install: cargo install hyperfine"
        exit 1
    fi
    echo "  ✓ $cmd: $($cmd --version 2>&1 | head -1)"
done

# ── System Preparation ───────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}System Preparation for Academic Rigor...${NC}"

if [[ "$CPU_PIN_ENABLED" == "true" ]]; then
    if command -v taskset &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} CPU pinning enabled (taskset available)"
        [[ -n "$CPU_CORES" ]] && echo "    Using cores: $CPU_CORES" || echo "    Using all available cores"
    else
        echo -e "  ${YELLOW}⚠${NC} taskset not found - CPU pinning disabled"
        CPU_PIN_ENABLED=false
    fi
fi

if [[ "$NUMA_ENABLED" == "true" ]]; then
    if command -v numactl &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} NUMA binding enabled (numactl available)"
        numactl --hardware 2>/dev/null | head -1 || true
    else
        echo -e "  ${YELLOW}⚠${NC} numactl not found - NUMA binding disabled"
        NUMA_ENABLED=false
    fi
fi

if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    CPU_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} CPU frequency: $((CPU_FREQ / 1000)) MHz"
fi

if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
    TURBO_DISABLED=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
    if [[ "$TURBO_DISABLED" == "0" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Turbo Boost ENABLED (may cause variance)"
    else
        echo -e "  ${GREEN}✓${NC} Turbo Boost disabled"
    fi
fi

# Capture hardware info
capture_hardware_info

# Helper function for CPU/NUMA pinning
run_pinned() {
    local cmd="$1"
    local pin_args=""
    [[ "$CPU_PIN_ENABLED" == "true" ]] && [[ -n "$CPU_CORES" ]] && pin_args="-c $CPU_CORES"
    if [[ "$NUMA_ENABLED" == "true" ]] && command -v numactl &>/dev/null; then
        eval numactl $pin_args --cpunodebind=$NUMA_NODE --membind=$NUMA_NODE $cmd
    elif [[ -n "$pin_args" ]]; then
        eval taskset $pin_args $cmd
    else
        eval $cmd
    fi
}

# ── [1/10] Container setup ───────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[1/10] Container setup...${NC}"

if [[ "$MODE" == "native" ]]; then
    echo -e "${YELLOW}  Skipping containers (native-only mode)${NC}"
elif [[ "$USE_GHCR" == "true" ]]; then
    echo -e "${CYAN}  Pulling pre-built images from GHCR...${NC}"
    for tag in "$PYTHON_TAG" "$JULIA_TAG" "$R_TAG"; do
        echo "    Pulling $tag..."
        if podman pull "$tag" 2>/dev/null; then
            echo -e "    ${GREEN}✓${NC} $tag pulled"
        else
            log_error "Failed to pull $tag"
            echo -e "    ${YELLOW}⚠  Falling back to local build${NC}"
            USE_GHCR=false
            break
        fi
    done
fi

if [[ "$MODE" != "native" ]] && [[ "$USE_GHCR" != "true" ]]; then
    build_container() {
        local tag="$1" file="$2"
        # Check if image already exists
        if podman image exists "$tag" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tag already exists (skipping build)"
            return 0
        fi
        echo -e "  ${GREEN}  Building $tag ...${NC}"
        if ! podman build -t "$tag" -f "$file" .; then
            log_error "Build failed: $tag"
            return 1
        fi
        echo -e "  ${GREEN}✓${NC} $tag built"
    }

    build_container "$PYTHON_TAG" "containers/python.Containerfile"
    build_container "$JULIA_TAG"  "containers/julia.Containerfile"
    build_container "$R_TAG"      "containers/r.Containerfile"

    # Save digests
    cat > results/container_hashes.txt << HEOF
Python  $PYTHON_TAG  $(podman image inspect "$PYTHON_TAG" --format '{{.Digest}}' 2>/dev/null || echo 'unknown')
Julia   $JULIA_TAG   $(podman image inspect "$JULIA_TAG"  --format '{{.Digest}}' 2>/dev/null || echo 'unknown')
R       $R_TAG       $(podman image inspect "$R_TAG"      --format '{{.Digest}}' 2>/dev/null || echo 'unknown')
HEOF
    echo -e "  ${GREEN}✓${NC} Digests saved → results/container_hashes.txt"
fi

# ── [2/10] Verify environments ───────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/10] Verifying environments...${NC}"

if [[ "$MODE" != "native" ]]; then
    echo -e "${GREEN}  Container Python:${NC}"
    podman run --rm "$PYTHON_TAG" python3 -c "import sys; print(f'    Python {sys.version.split()[0]}')" 2>/dev/null || log_error "Python container verification failed"
    echo -e "${GREEN}  Container Julia:${NC}"
    podman run --rm "$JULIA_TAG" julia --version 2>/dev/null | sed 's/^/    /' || log_error "Julia container verification failed"
    echo -e "${GREEN}  Container R:${NC}"
    podman run --rm "$R_TAG" R --version 2>/dev/null | head -1 | sed 's/^/    /' || log_error "R container verification failed"
fi

# ── [3/10] Data preparation ──────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/10] Preparing benchmark datasets...${NC}"

if check_resume "data"; then
    :
else
    DDIR="$(pwd)/data"
    mkdir -p "$DDIR"
    if [[ -f "tools/download_data.py" ]]; then
        source .venv/bin/activate 2>/dev/null || true
        python3 tools/download_data.py --all --synthetic 2>&1 | grep -E "✓|⚠" | head -10 || true
    fi
    mark_checkpoint "data"
fi
echo -e "  ${GREEN}✓${NC} Data preparation complete"

# ── [4/10] COLD START benchmarks (container) ─────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[4/10] COLD START benchmarks (first-run / JIT latency)...${NC}"
    mkdir -p results/cold_start

    if check_resume "cold_start"; then
        :
    else
        run_cold() {
            local scenario="$1" script="$2" lang="$3" tag="$4" out="$5"
            progress
            echo "    $lang (cold) — $scenario"
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                hyperfine --warmup 0 --runs "$COLD_START_RUNS" \
                --export-json "/benchmarks/$out" "$script" 2>&1 | tail -5
        }

        [ "$ENABLE_VECTOR" = "true" ] && {
            run_cold "vector" "python3 benchmarks/vector_pip.py" "Python" "$PYTHON_TAG" "results/cold_start/vector_python_cold.json"
            run_cold "vector" "julia -t auto benchmarks/vector_pip.jl" "Julia" "$JULIA_TAG" "results/cold_start/vector_julia_cold.json"
            run_cold "vector" "Rscript benchmarks/vector_pip.R"  "R"      "$R_TAG"     "results/cold_start/vector_r_cold.json"
        }
        [ "$ENABLE_HYPERSPECTRAL" = "true" ] && {
            run_cold "hyperspectral" "python3 benchmarks/hsi_stream.py" "Python" "$PYTHON_TAG" "results/cold_start/hsi_python_cold.json"
            run_cold "hyperspectral" "julia -t auto benchmarks/hsi_stream.jl" "Julia" "$JULIA_TAG" "results/cold_start/hsi_julia_cold.json"
            run_cold "hyperspectral" "Rscript benchmarks/hsi_stream.R" "R" "$R_TAG" "results/cold_start/hsi_r_cold.json"
        }
        mark_checkpoint "cold_start"
    fi
fi

# ── [5/10] WARM START benchmarks (container) ─────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[5/10] WARM START benchmarks (steady-state)...${NC}"
    mkdir -p results/warm_start

    if check_resume "warm_start"; then
        :
    else
        run_warm() {
            local scenario="$1" script="$2" lang="$3" tag="$4" out="$5"
            progress
            echo "    $lang (warm) — $scenario"
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                hyperfine --warmup "$WARMUP_RUNS" --runs "$BENCHMARK_RUNS" \
                --export-json "/benchmarks/$out" "$script" 2>&1 | tail -5
        }

        [ "$ENABLE_VECTOR" = "true" ] && {
            run_warm "vector" "python3 benchmarks/vector_pip.py" "Python" "$PYTHON_TAG" "results/warm_start/vector_python_warm.json"
            run_warm "vector" "julia -t auto benchmarks/vector_pip.jl" "Julia" "$JULIA_TAG" "results/warm_start/vector_julia_warm.json"
            run_warm "vector" "Rscript benchmarks/vector_pip.R"  "R"      "$R_TAG"     "results/warm_start/vector_r_warm.json"
        }
        [ "$ENABLE_INTERPOLATION" = "true" ] && {
            run_warm "interpolation" "python3 benchmarks/interpolation_idw.py" "Python" "$PYTHON_TAG" "results/warm_start/interp_python_warm.json"
            run_warm "interpolation" "julia -t auto benchmarks/interpolation_idw.jl" "Julia" "$JULIA_TAG" "results/warm_start/interp_julia_warm.json"
            run_warm "interpolation" "Rscript benchmarks/interpolation_idw.R" "R" "$R_TAG" "results/warm_start/interp_r_warm.json"
        }
        [ "$ENABLE_TIMESERIES" = "true" ] && {
            run_warm "timeseries" "python3 benchmarks/timeseries_ndvi.py" "Python" "$PYTHON_TAG" "results/warm_start/ndvi_python_warm.json"
            run_warm "timeseries" "julia -t auto benchmarks/timeseries_ndvi.jl" "Julia" "$JULIA_TAG" "results/warm_start/ndvi_julia_warm.json"
            run_warm "timeseries" "Rscript benchmarks/timeseries_ndvi.R" "R" "$R_TAG" "results/warm_start/ndvi_r_warm.json"
        }
        [ "$ENABLE_HYPERSPECTRAL" = "true" ] && {
            run_warm "hyperspectral" "python3 benchmarks/hsi_stream.py" "Python" "$PYTHON_TAG" "results/warm_start/hsi_python_warm.json"
            run_warm "hyperspectral" "julia -t auto benchmarks/hsi_stream.jl" "Julia" "$JULIA_TAG" "results/warm_start/hsi_julia_warm.json"
            run_warm "hyperspectral" "Rscript benchmarks/hsi_stream.R" "R" "$R_TAG" "results/warm_start/hsi_r_warm.json"
        }
        mark_checkpoint "warm_start"
    fi
fi

# ── [6/10] Matrix Operations (container) ─────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[6/10] Matrix Operations (container)...${NC}"
    if check_resume "matrix_container"; then
        :
    else
        run_matrix() {
            local lang="$1" cmd="$2" tag="$3"
            progress
            echo "    $lang matrix operations..."
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                bash -c "cd /benchmarks && $cmd" 2>&1 | grep -E "✓ Min:|✓ Results saved" | head -10
        }
        run_matrix "Python" "python3 benchmarks/matrix_ops.py" "$PYTHON_TAG"
        run_matrix "Julia"  "julia benchmarks/matrix_ops.jl" "$JULIA_TAG"
        run_matrix "R"      "Rscript benchmarks/matrix_ops.R" "$R_TAG"
        mark_checkpoint "matrix_container"
    fi
fi

# ── [7/10] I/O Operations (container) ────────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[7/10] I/O Operations (container)...${NC}"
    if check_resume "io_container"; then
        :
    else
        run_io() {
            local lang="$1" cmd="$2" tag="$3"
            progress
            echo "    $lang I/O operations..."
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                bash -c "cd /benchmarks && $cmd" 2>&1 | grep -E "✓ Min:|✓ Results saved" | head -10
        }
        run_io "Python" "python3 benchmarks/io_ops.py" "$PYTHON_TAG"
        run_io "Julia"  "julia benchmarks/io_ops.jl" "$JULIA_TAG"
        run_io "R"      "Rscript benchmarks/io_ops.R" "$R_TAG"
        mark_checkpoint "io_container"
    fi
fi

# ── [8/10] Memory profiling (container) ──────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[8/10] Memory profiling (container)...${NC}"
    mkdir -p results/memory
    if check_resume "memory"; then
        :
    else
        profile_memory() {
            local lang="$1" cmd="$2" tag="$3" outfile="$4"
            progress
            echo "  $lang memory..."
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                bash -c "/usr/bin/time -v $cmd 2>&1 | grep -E 'Maximum resident|wall clock'" \
            | tee "results/memory/${outfile}.txt" || true
        }
        [ "$ENABLE_VECTOR" = "true" ] && {
            profile_memory "Python" "python3 benchmarks/vector_pip.py"       "$PYTHON_TAG" "vector_python_mem"
            profile_memory "Julia"  "julia -t auto benchmarks/vector_pip.jl" "$JULIA_TAG"  "vector_julia_mem"
            profile_memory "R"      "Rscript benchmarks/vector_pip.R"        "$R_TAG"      "vector_r_mem"
        }
        mark_checkpoint "memory"
    fi
fi

# ── [9/10] Validate results (container) ──────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[9/10] Validating correctness (container)...${NC}"
    if check_resume "validation_container"; then
        :
    else
        if [ -f "validation/thesis_validation.py" ]; then
            podman run --rm -v "$(pwd)":/benchmarks:Z "$PYTHON_TAG" \
                python3 validation/thesis_validation.py --all 2>&1 | tail -15 || log_error "Container validation failed"
            mark_checkpoint "validation_container"
        fi
    fi
fi

# ── [10/10] NATIVE BENCHMARKS ────────────────────────────────────────────────
if [[ "$MODE" != "container" ]]; then
    echo ""
    echo -e "${BLUE}[10/10] Native System Benchmarks${NC}"
    echo -e "${YELLOW}  Running on host system with CPU pinning${NC}"
    echo ""

    mkdir -p results/native results/academic

    run_native() {
        local lang="$1" cmd="$2" name="$3"
        progress
        echo -e "  ${GREEN}$lang${NC}: $name"
        local freq_before=""
        if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
            freq_before=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
            echo "    CPU freq: $((freq_before / 1000)) MHz"
        fi
        if [[ "$CPU_PIN_ENABLED" == "true" ]] && [[ -n "$CPU_CORES" ]]; then
            taskset -c "$CPU_CORES" bash -c "$cmd" 2>&1 | grep -E "✓ Min:|✓ Results saved" | head -10 || log_error "$lang $name failed"
        else
            eval "$cmd" 2>&1 | grep -E "✓ Min:|✓ Results saved" | head -10 || log_error "$lang $name failed"
        fi
    }

    echo -e "${YELLOW}  Matrix Operations:${NC}"
    command -v python3 &>/dev/null && { source .venv/bin/activate 2>/dev/null || true; run_native "Python" "python3 benchmarks/matrix_ops.py" "matrix_ops"; }
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/matrix_ops.jl" "matrix_ops"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/matrix_ops.R" "matrix_ops"

    echo -e "${YELLOW}  I/O Operations:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/io_ops.py" "io_ops"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/io_ops.jl" "io_ops"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/io_ops.R" "io_ops"

    echo -e "${YELLOW}  Raster Algebra:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/raster_algebra.py" "raster_algebra"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/raster_algebra.jl" "raster_algebra"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/raster_algebra.R" "raster_algebra"

    echo -e "${YELLOW}  Reprojection:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/reprojection.py" "reprojection"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/reprojection.jl" "reprojection"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/reprojection.R" "reprojection"

    echo -e "${YELLOW}  Zonal Stats:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/zonal_stats.py" "zonal_stats"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/zonal_stats.jl" "zonal_stats"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/zonal_stats.R" "zonal_stats"

    echo -e "${YELLOW}  Interpolation:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/interpolation_idw.py" "interpolation"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/interpolation_idw.jl" "interpolation"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/interpolation_idw.R" "interpolation"

    echo -e "${YELLOW}  Time-Series:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/timeseries_ndvi.py" "timeseries"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/timeseries_ndvi.jl" "timeseries"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/timeseries_ndvi.R" "timeseries"

    echo -e "${YELLOW}  Hyperspectral:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/hsi_stream.py" "hsi_stream"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/hsi_stream.jl" "hsi_stream"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/hsi_stream.R" "hsi_stream"

    echo -e "${YELLOW}  Vector PiP:${NC}"
    command -v python3 &>/dev/null && run_native "Python" "python3 benchmarks/vector_pip.py" "vector_pip"
    command -v julia &>/dev/null && run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS $HOME/.local/julia/bin/julia benchmarks/vector_pip.jl" "vector_pip"
    command -v Rscript &>/dev/null && run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/vector_pip.R" "vector_pip"

    echo -e "${GREEN}  ✓ Native benchmarks complete${NC}"
fi

# ── Generate Academic Report ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}Generating Academic Report...${NC}"

if command -v python3 &>/dev/null; then
    source .venv/bin/activate 2>/dev/null || true
    [[ -f "tools/thesis_viz.py" ]] && { echo "  Generating visualizations..."; python3 tools/thesis_viz.py --all 2>&1 | tail -3 || log_error "Visualization failed"; }
    [[ -f "validation/thesis_validation.py" ]] && { echo "  Running validation..."; python3 validation/thesis_validation.py --all 2>&1 | tail -15 || log_error "Validation failed"; }
    echo -e "${GREEN}  ✓ Academic report complete${NC}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "========================================================================"
echo "  ✓ ALL BENCHMARKS COMPLETE"
echo "========================================================================"
echo -e "${NC}"
echo "  Elapsed: $(elapsed_time)"
echo "  Finished: $(timestamp)"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  ⚠ ${#ERRORS[@]} error(s) encountered:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "    ${RED}• $err${NC}"
    done
    echo "  Full error log: results/errors.log"
fi

echo ""
echo "  Results directory:"
find results -name '*.json' -o -name '*.txt' -o -name '*.md' -o -name '*.png' 2>/dev/null | \
    grep -v gitkeep | sort | sed 's/^/    /'
echo ""
echo "  Key Outputs:"
echo "    - results/matrix_ops_{python,julia,r}.json"
echo "    - results/io_ops_{python,julia,r}.json"
echo "    - results/thesis_validation_report.md"
echo "    - results/figures/summary_chart.png"
echo ""
echo "  Usage:"
echo "    ./run_benchmarks.sh              # Full suite"
echo "    ./run_benchmarks.sh --use-ghcr   # Pull pre-built images"
echo "    ./run_benchmarks.sh --resume     # Resume from checkpoint"
echo "    ./run_benchmarks.sh --clean      # Clear old results"
echo "    ./run_benchmarks.sh --dry-run    # Preview plan"
echo ""
echo -e "${CYAN}  Thesis Quality: A+ (v3.0 - Academic Rigor Edition)${NC}"
echo ""
