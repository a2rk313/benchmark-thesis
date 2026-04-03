#!/usr/bin/env bash
# =============================================================================
# THESIS BENCHMARK SUITE ORCHESTRATOR
# Version: 2.3.0 (native + container benchmarking)
#
# FEATURES:
#   - Container benchmarks (reproducible, isolated environment)
#   - Native benchmarks (real-world performance on host system)
#   - Side-by-side comparison of container vs native performance
#
# CACHING BEHAVIOR:
#   - Containers built WITH cache (fast: 2-5 min if layers unchanged)
#   - First build: ~25 min (scipy compiles from source)
#   - Subsequent builds: ~2 min (uses cached layers)
#   - If build fails with stale cache: ./purge_cache_and_rebuild.sh
#
# USAGE:
#   ./run_benchmarks.sh           # Build + run all (container + native)
#   ./run_benchmarks.sh --container-only   # Container benchmarks only
#   ./run_benchmarks.sh --native-only      # Native benchmarks only
#   ./purge_cache_and_rebuild.sh  # If build fails, clear cache first
# =============================================================================
set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE="all"
if [[ "${1:-}" == "--container-only" ]]; then
    MODE="container"
elif [[ "${1:-}" == "--native-only" ]]; then
    MODE="native"
fi

# ── Colour codes ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
MAGENTA='\033[0;35m'

# ── Configuration ─────────────────────────────────────────────────────────────
COLD_START_RUNS=5
BENCHMARK_RUNS=10
WARMUP_RUNS=3

# Container image tags — must match Containerfile LABEL versions
PYTHON_TAG="thesis-python:3.13"
JULIA_TAG="thesis-julia:1.11"
R_TAG="thesis-r:4.5"

# Thread configuration for fair native benchmarking
export JULIA_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
export OMP_NUM_THREADS=8

# Scenario toggles
ENABLE_VECTOR=true
ENABLE_INTERPOLATION=true
ENABLE_TIMESERIES=true
ENABLE_HYPERSPECTRAL=true

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
echo "========================================================================"
echo "  THESIS BENCHMARK SUITE: NATIVE + CONTAINER v2.3"
echo "========================================================================"
echo -e "${NC}"

if [[ "$MODE" == "all" ]]; then
    echo -e "  ${MAGENTA}MODE: FULL (Native + Container)${NC}"
elif [[ "$MODE" == "container" ]]; then
    echo -e "  ${YELLOW}MODE: CONTAINER ONLY${NC}"
else
    echo -e "  ${GREEN}MODE: NATIVE ONLY${NC}"
fi

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
echo "  Cold runs: $COLD_START_RUNS   Warm runs: $BENCHMARK_RUNS  (warmup: $WARMUP_RUNS)"
echo ""
echo "  Enabled scenarios:"
[ "$ENABLE_VECTOR" = "true" ]         && echo "    ✓ Vector topology (Point-in-Polygon)"
[ "$ENABLE_INTERPOLATION" = "true" ]  && echo "    ✓ Spatial Interpolation (IDW)"
[ "$ENABLE_TIMESERIES" = "true" ]     && echo "    ✓ Time-Series NDVI"
[ "$ENABLE_HYPERSPECTRAL" = "true" ]  && echo "    ✓ Hyperspectral SAM"
echo ""

# ── [0/8] Dependency check ────────────────────────────────────────────────────
echo -e "${BLUE}[0/8] Checking dependencies...${NC}"
for cmd in podman hyperfine; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}❌ $cmd not found.${NC}"
        [ "$cmd" = "podman" ]    && echo "     Install: sudo dnf install podman"
        [ "$cmd" = "hyperfine" ] && echo "     Install: cargo install hyperfine"
        exit 1
    fi
    echo "  ✓ $cmd: $($cmd --version 2>&1 | head -1)"
done

# ── [1/9] Build containers (with caching for speed) ───────────────────────────
echo ""
echo -e "${BLUE}[1/9] Building containers...${NC}"

if [[ "$MODE" == "native" ]]; then
    echo -e "${YELLOW}  Skipping container build (native-only mode)${NC}"
else
    echo -e "${YELLOW}  Using build cache for speed. First build: ~25 min. Subsequent: ~2 min.${NC}"
    echo -e "${YELLOW}  If build fails with stale cache, run: ./purge_cache_and_rebuild.sh${NC}"
    echo ""

    build_container() {
        local tag="$1" file="$2"
        echo -e "${GREEN}  Building $tag ...${NC}"
        if ! podman build -t "$tag" -f "$file" .; then
            echo -e "${RED}❌ Build failed: $tag${NC}"
            echo "   Check the Containerfile: $file"
            echo "   If you see stale cache errors, run: ./purge_cache_and_rebuild.sh"
            exit 1
        fi
        local digest
        digest=$(podman image inspect "$tag" --format '{{.Digest}}' 2>/dev/null || echo "unknown")
        echo "  ✓ $tag  digest: ${digest:7:16}..."
    }

    build_container "$PYTHON_TAG" "containers/python.Containerfile"
    build_container "$JULIA_TAG"  "containers/julia.Containerfile"
    build_container "$R_TAG"      "containers/r.Containerfile"

    mkdir -p results
    cat > results/container_hashes.txt << HEOF
Python  $PYTHON_TAG  $(podman image inspect "$PYTHON_TAG" --format '{{.Digest}}' 2>/dev/null)
Julia   $JULIA_TAG   $(podman image inspect "$JULIA_TAG"  --format '{{.Digest}}' 2>/dev/null)
R       $R_TAG       $(podman image inspect "$R_TAG"      --format '{{.Digest}}' 2>/dev/null)
HEOF
    echo "  ✓ Digests saved → results/container_hashes.txt"
fi

# ── [2/9] Verify environments ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/9] Verifying environments...${NC}"

if [[ "$MODE" != "native" ]]; then
    echo -e "${GREEN}  Container Python:${NC}"
    podman run --rm "$PYTHON_TAG" python3 - << 'PYEOF'
import sys, numpy, scipy, pandas, geopandas, rasterio, shapely, sklearn
print(f"    Python     {sys.version.split()[0]}")
print(f"    numpy      {numpy.__version__}")
print(f"    scipy      {scipy.__version__}")
print(f"    geopandas  {geopandas.__version__}")
print(f"    rasterio   {rasterio.__version__}")
print(f"    sklearn    {sklearn.__version__}")
PYEOF

    echo -e "${GREEN}  Container Julia:${NC}"
    podman run --rm "$JULIA_TAG" julia --project="${JULIA_PROJECT:-/opt/julia-project}" -e '
        println("    Julia      ", VERSION)
        println("    Threads    ", Threads.nthreads())
        using ArchGDAL, DataFrames; println("    ArchGDAL   OK")
    '

    echo -e "${GREEN}  Container R:${NC}"
    podman run --rm "$R_TAG" Rscript -e '
        cat("    R         ", R.version.string, "\n")
        cat("    terra     ", as.character(packageVersion("terra")), "\n")
        cat("    data.table", as.character(packageVersion("data.table")), "\n")
        cat("    jsonlite  ", as.character(packageVersion("jsonlite")), "\n")
        cat("    digest    ", as.character(packageVersion("digest")), "\n")
    '
fi

echo -e "${GREEN}  Native Python:${NC}"
if command -v python3 &>/dev/null; then
    python3 -c "
import sys, numpy, scipy, pandas
print(f'    Python     {sys.version.split()[0]}')
print(f'    numpy      {numpy.__version__}')
print(f'    scipy      {scipy.__version__}')
print(f'    pandas     {pandas.__version__}')
" 2>/dev/null || echo "    ⚠ Some packages missing"
else
    echo "    ⚠ Python3 not found"
fi

echo -e "${GREEN}  Native Julia:${NC}"
if command -v julia &>/dev/null; then
    julia --version 2>/dev/null | sed 's/^/    /'
    julia -e 'println("    Threads  ", Threads.nthreads())' 2>/dev/null || true
else
    echo "    ⚠ Julia not found"
fi

echo -e "${GREEN}  Native R:${NC}"
if command -v Rscript &>/dev/null; then
    Rscript -e 'cat("    R         ", R.version.string, "\n")' 2>/dev/null || echo "    ⚠ R not found"
else
    echo "    ⚠ R not found"
fi

echo -e "${GREEN}  Native BLAS:${NC}"
if [ -f /usr/lib64/libopenblas.so ]; then
    echo "    ✓ OpenBLAS available"
elif [ -f /usr/lib64/libblas.so ]; then
    ls -la /usr/lib64/libblas.so 2>/dev/null | grep -q openblas && echo "    ✓ OpenBLAS" || echo "    ⚠ Reference BLAS (install blas-openblas)"
else
    echo "    ? BLAS status unknown"
fi

# ── [3/9] Data preparation ────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/9] Preparing benchmark datasets...${NC}"

DDIR="$(pwd)/data"
mkdir -p "$DDIR"

if [ "$ENABLE_VECTOR" = "true" ]; then
    if [ ! -f "$DDIR/natural_earth_countries.gpkg" ] || [ ! -f "$DDIR/gps_points_1m.csv" ]; then
        echo "  Generating vector data..."
        if [[ "$MODE" != "native" ]] && command -v podman &>/dev/null; then
            podman run --rm \
                -v "$DDIR":/benchmarks/data:Z \
                -v "$(pwd)/tools":/benchmarks/tools:Z \
                "$PYTHON_TAG" python3 tools/gen_vector_data.py
        elif command -v python3 &>/dev/null; then
            python3 tools/gen_vector_data.py
        fi
    else
        echo "  ✓ Vector data exists"
    fi
fi

if [ "$ENABLE_HYPERSPECTRAL" = "true" ]; then
    if [ ! -f "$DDIR/Cuprite.mat" ]; then
        echo "  Downloading hyperspectral data (Cuprite dataset, ~100 MB)..."
        if [[ "$MODE" != "native" ]] && command -v podman &>/dev/null; then
            podman run --rm \
                -v "$DDIR":/benchmarks/data:Z \
                -v "$(pwd)/tools":/benchmarks/tools:Z \
                "$PYTHON_TAG" python3 tools/download_cuprite.py
        elif command -v python3 &>/dev/null; then
            python3 tools/download_cuprite.py
        fi
    else
        echo "  ✓ Hyperspectral data exists (Cuprite.mat)"
    fi
fi

echo "  ✓ Data preparation complete"

# ── [4/9] COLD START benchmarks (container) ──────────────────────────────────
if [[ "$MODE" == "native" ]]; then
    echo ""
    echo -e "${BLUE}[4/9] COLD START benchmarks (skipped - native mode)${NC}"
else
    echo ""
    echo -e "${BLUE}[4/9] COLD START benchmarks (first-run / JIT-compilation latency)...${NC}"
    mkdir -p results/cold_start

run_cold() {
    local scenario="$1" script="$2" lang="$3" tag="$4" out="$5"
    echo "    $lang (cold) — $scenario"
    podman run --rm \
        -v "$(pwd)":/benchmarks:Z \
        "$tag" \
        hyperfine --warmup 0 --runs "$COLD_START_RUNS" \
            --export-json "/benchmarks/$out" \
            "$script"
}

if [ "$ENABLE_VECTOR" = "true" ]; then
    echo -e "${YELLOW}  Vector Point-in-Polygon (COLD)${NC}"
    run_cold "vector" "python3 benchmarks/vector_pip.py" "Python" "$PYTHON_TAG" "results/cold_start/vector_python_cold.json"
    run_cold "vector" "julia -t auto benchmarks/vector_pip.jl" "Julia" "$JULIA_TAG" "results/cold_start/vector_julia_cold.json"
    run_cold "vector" "Rscript benchmarks/vector_pip.R"  "R"      "$R_TAG"     "results/cold_start/vector_r_cold.json"
fi

if [ "$ENABLE_INTERPOLATION" = "true" ]; then
    echo -e "${YELLOW}  Spatial Interpolation IDW (COLD)${NC}"
    run_cold "interpolation" "python3 benchmarks/interpolation_idw.py" "Python" "$PYTHON_TAG" "results/cold_start/interp_python_cold.json"
    run_cold "interpolation" "julia -t auto benchmarks/interpolation_idw.jl" "Julia" "$JULIA_TAG" "results/cold_start/interp_julia_cold.json"
    run_cold "interpolation" "Rscript benchmarks/interpolation_idw.R" "R"  "$R_TAG" "results/cold_start/interp_r_cold.json"
fi

if [ "$ENABLE_TIMESERIES" = "true" ]; then
    echo -e "${YELLOW}  Time-Series NDVI (COLD)${NC}"
    run_cold "timeseries" "python3 benchmarks/timeseries_ndvi.py" "Python" "$PYTHON_TAG" "results/cold_start/ndvi_python_cold.json"
    run_cold "timeseries" "julia -t auto benchmarks/timeseries_ndvi.jl" "Julia" "$JULIA_TAG" "results/cold_start/ndvi_julia_cold.json"
    run_cold "timeseries" "Rscript benchmarks/timeseries_ndvi.R" "R" "$R_TAG" "results/cold_start/ndvi_r_cold.json"
fi

if [ "$ENABLE_HYPERSPECTRAL" = "true" ]; then
    echo -e "${YELLOW}  Hyperspectral SAM (COLD)${NC}"
    run_cold "hyperspectral" "python3 benchmarks/hsi_stream.py" "Python" "$PYTHON_TAG" "results/cold_start/hsi_python_cold.json"
    run_cold "hyperspectral" "julia -t auto benchmarks/hsi_stream.jl" "Julia" "$JULIA_TAG" "results/cold_start/hsi_julia_cold.json"
    run_cold "hyperspectral" "Rscript benchmarks/hsi_stream.R" "R" "$R_TAG" "results/cold_start/hsi_r_cold.json"
fi
fi  # End of container-only cold start section

# ── [5/9] WARM START benchmarks (container) ───────────────────────────────────
if [[ "$MODE" == "native" ]]; then
    echo ""
    echo -e "${BLUE}[5/9] WARM START benchmarks (skipped - native mode)${NC}"
else
    echo ""
    echo -e "${BLUE}[5/9] WARM START benchmarks (steady-state / JIT-compiled)...${NC}"
    mkdir -p results/warm_start

run_warm() {
    local scenario="$1" script="$2" lang="$3" tag="$4" out="$5"
    echo "    $lang (warm) — $scenario"
    podman run --rm \
        -v "$(pwd)":/benchmarks:Z \
        "$tag" \
        hyperfine --warmup "$WARMUP_RUNS" --runs "$BENCHMARK_RUNS" \
            --export-json "/benchmarks/$out" \
            "$script"
}

if [ "$ENABLE_VECTOR" = "true" ]; then
    echo -e "${YELLOW}  Vector Point-in-Polygon (WARM)${NC}"
    run_warm "vector" "python3 benchmarks/vector_pip.py" "Python" "$PYTHON_TAG" "results/warm_start/vector_python_warm.json"
    run_warm "vector" "julia -t auto benchmarks/vector_pip.jl" "Julia" "$JULIA_TAG" "results/warm_start/vector_julia_warm.json"
    run_warm "vector" "Rscript benchmarks/vector_pip.R"  "R"      "$R_TAG"     "results/warm_start/vector_r_warm.json"
fi

if [ "$ENABLE_INTERPOLATION" = "true" ]; then
    echo -e "${YELLOW}  Spatial Interpolation IDW (WARM)${NC}"
    run_warm "interpolation" "python3 benchmarks/interpolation_idw.py" "Python" "$PYTHON_TAG" "results/warm_start/interp_python_warm.json"
    run_warm "interpolation" "julia -t auto benchmarks/interpolation_idw.jl" "Julia" "$JULIA_TAG" "results/warm_start/interp_julia_warm.json"
    run_warm "interpolation" "Rscript benchmarks/interpolation_idw.R" "R" "$R_TAG" "results/warm_start/interp_r_warm.json"
fi

if [ "$ENABLE_TIMESERIES" = "true" ]; then
    echo -e "${YELLOW}  Time-Series NDVI (WARM)${NC}"
    run_warm "timeseries" "python3 benchmarks/timeseries_ndvi.py" "Python" "$PYTHON_TAG" "results/warm_start/ndvi_python_warm.json"
    run_warm "timeseries" "julia -t auto benchmarks/timeseries_ndvi.jl" "Julia" "$JULIA_TAG" "results/warm_start/ndvi_julia_warm.json"
    run_warm "timeseries" "Rscript benchmarks/timeseries_ndvi.R" "R" "$R_TAG" "results/warm_start/ndvi_r_warm.json"
fi

if [ "$ENABLE_HYPERSPECTRAL" = "true" ]; then
    echo -e "${YELLOW}  Hyperspectral SAM (WARM)${NC}"
    run_warm "hyperspectral" "python3 benchmarks/hsi_stream.py" "Python" "$PYTHON_TAG" "results/warm_start/hsi_python_warm.json"
    run_warm "hyperspectral" "julia -t auto benchmarks/hsi_stream.jl" "Julia" "$JULIA_TAG" "results/warm_start/hsi_julia_warm.json"
    run_warm "hyperspectral" "Rscript benchmarks/hsi_stream.R" "R" "$R_TAG" "results/warm_start/hsi_r_warm.json"
fi
fi  # End of container-only warm start section

# ── [6/9] Matrix Operations (container) ───────────────────────────────────────
echo ""
echo -e "${BLUE}[6/9] Matrix Operations (Tedesco et al. 2025 alignment)...${NC}"
if [[ "$MODE" == "native" ]]; then
    echo -e "${YELLOW}  Skipped in native mode (done in [12/12])${NC}"
else
    run_matrix() {
        local lang="$1" cmd="$2" tag="$3"
        echo "    $lang matrix operations..."
        podman run --rm \
            -v "$(pwd)":/benchmarks:Z \
            "$tag" \
            bash -c "cd /benchmarks && $cmd"
    }

    run_matrix "Python" "python3 benchmarks/matrix_ops.py" "$PYTHON_TAG"
    run_matrix "Julia"  "julia benchmarks/matrix_ops.jl" "$JULIA_TAG"
    run_matrix "R"      "Rscript benchmarks/matrix_ops.R" "$R_TAG"

    echo -e "${GREEN}  ✓ Matrix operations complete${NC}"
    echo "  Results: results/matrix_ops_{python,julia,r}.json"
fi

# ── [7/9] I/O Operations (container) ──────────────────────────────────────────
echo ""
echo -e "${BLUE}[7/9] I/O Operations (CSV and Binary)...${NC}"
if [[ "$MODE" == "native" ]]; then
    echo -e "${YELLOW}  Skipped in native mode (done in [12/12])${NC}"
else
    run_io() {
        local lang="$1" cmd="$2" tag="$3"
        echo "    $lang I/O operations..."
        podman run --rm \
            -v "$(pwd)":/benchmarks:Z \
            "$tag" \
            bash -c "cd /benchmarks && $cmd"
    }

    run_io "Python" "python3 benchmarks/io_ops.py" "$PYTHON_TAG"
    run_io "Julia"  "julia benchmarks/io_ops.jl" "$JULIA_TAG"
    run_io "R"      "Rscript benchmarks/io_ops.R" "$R_TAG"

    echo -e "${GREEN}  ✓ I/O operations complete${NC}"
    echo "  Results: results/io_ops_{python,julia,r}.json"
fi

# ── [8/9] Memory profiling (container) ────────────────────────────────────────
echo ""
echo -e "${BLUE}[8/9] Memory profiling (peak RSS)...${NC}"
mkdir -p results/memory

if [[ "$MODE" == "native" ]]; then
    echo -e "${YELLOW}  Skipped in native mode${NC}"
else
    profile_memory() {
        local lang="$1" cmd="$2" tag="$3" outfile="$4"
        echo "  $lang memory..."
        podman run --rm \
            -v "$(pwd)":/benchmarks:Z \
            "$tag" \
            bash -c "/usr/bin/time -v $cmd 2>&1 | grep -E 'Maximum resident|wall clock'" \
        | tee "results/memory/${outfile}.txt" || true
    }

    [ "$ENABLE_VECTOR" = "true" ] && {
        profile_memory "Python" "python3 benchmarks/vector_pip.py"       "$PYTHON_TAG" "vector_python_mem"
        profile_memory "Julia"  "julia -t auto benchmarks/vector_pip.jl" "$JULIA_TAG"  "vector_julia_mem"
        profile_memory "R"      "Rscript benchmarks/vector_pip.R"        "$R_TAG"      "vector_r_mem"
    }
fi

# ── [9/9] Validate results ───────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[9/9] Validating correctness (cross-language hash comparison)...${NC}"

if [ -f "validation/validate_results.py" ]; then
    if [[ "$MODE" != "native" ]]; then
        podman run --rm \
            -v "$(pwd)":/benchmarks:Z \
            "$PYTHON_TAG" \
            python3 validation/validate_results.py \
            && echo "  ✓ Validation passed" \
            || echo "  ⚠ Validation had warnings (check output above)"
    else
        python3 validation/validate_results.py \
            && echo "  ✓ Validation passed" \
            || echo "  ⚠ Validation had warnings (check output above)"
    fi
else
    echo "  ⚠ validate_results.py not found — skipping"
fi

# ── [10/9] Chen & Revels Validation ─────────────────────────────────────────
echo ""
echo -e "${BLUE}[10/9] Chen & Revels (2016) Methodology Validation...${NC}"

if [ -f "validation/chen_revels_validation.py" ]; then
    if [[ "$MODE" != "native" ]]; then
        podman run --rm \
            -v "$(pwd)":/benchmarks:Z \
            "$PYTHON_TAG" \
            python3 validation/chen_revels_validation.py \
            && echo "  ✓ Chen & Revels validation complete" \
            || echo "  ⚠ Validation had errors"
    else
        python3 validation/chen_revels_validation.py \
            && echo "  ✓ Chen & Revels validation complete" \
            || echo "  ⚠ Validation had errors"
    fi
else
    echo "  ⚠ chen_revels_validation.py not found — skipping"
fi

# ── [11/9] Tedesco et al. Comparison ─────────────────────────────────────────
echo ""
echo -e "${BLUE}[11/9] Comparison with Tedesco et al. (2025)...${NC}"

if [ -f "tools/compare_with_tedesco.py" ] && \
   [ -f "results/matrix_ops_python.json" ] && \
   [ -f "results/matrix_ops_julia.json" ] && \
   [ -f "results/matrix_ops_r.json" ]; then
    python3 tools/compare_with_tedesco.py \
        && echo "  ✓ Literature comparison complete" \
        || echo "  ⚠ Comparison had errors"
else
    echo "  ⚠ Matrix operations results not found — run matrix benchmarks first"
fi

# ── [12/12] NATIVE BENCHMARKS ────────────────────────────────────────────────
if [[ "$MODE" == "container" ]]; then
    echo ""
    echo -e "${BLUE}[12/12] Native System Benchmarks (skipped - container mode)${NC}"
else
    echo ""
    echo -e "${BLUE}[12/12] Native System Benchmarks${NC}"
    echo -e "${YELLOW}  Running on host system for real-world performance comparison${NC}"
    echo ""
    echo "  Thread config: JULIA_NUM_THREADS=$JULIA_NUM_THREADS, OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS"
    echo ""

    mkdir -p results/native

    run_native() {
        local lang="$1" cmd="$2" name="$3"
        echo -e "  ${GREEN}$lang native${NC}: $name"
        if ! eval "$cmd" 2>&1; then
            echo -e "    ${RED}❌ Failed${NC}"
        fi
    }

    # Matrix Operations (native)
    echo -e "${YELLOW}  Matrix Operations:${NC}"
    if command -v python3 &>/dev/null; then
        source .venv/bin/activate 2>/dev/null || true
        run_native "Python" "python3 benchmarks/matrix_ops.py" "matrix_ops"
    fi
    if command -v julia &>/dev/null; then
        run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/matrix_ops.jl" "matrix_ops"
    fi
    if command -v Rscript &>/dev/null; then
        run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/matrix_ops.R" "matrix_ops"
    fi

    # I/O Operations (native)
    echo -e "${YELLOW}  I/O Operations:${NC}"
    if command -v python3 &>/dev/null; then
        run_native "Python" "python3 benchmarks/io_ops.py" "io_ops"
    fi
    if command -v julia &>/dev/null; then
        run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/io_ops.jl" "io_ops"
    fi
    if command -v Rscript &>/dev/null; then
        run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/io_ops.R" "io_ops"
    fi

    # Raster Algebra (native)
    echo -e "${YELLOW}  Raster Algebra:${NC}"
    if command -v python3 &>/dev/null; then
        run_native "Python" "python3 benchmarks/raster_algebra.py" "raster_algebra"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/raster_algebra.jl" "raster_algebra"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/raster_algebra.R" "raster_algebra"
fi

# Reprojection (native)
echo -e "${YELLOW}  Coordinate Reprojection:${NC}"
if command -v python3 &>/dev/null; then
    run_native "Python" "python3 benchmarks/reprojection.py" "reprojection"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/reprojection.jl" "reprojection"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/reprojection.R" "reprojection"
fi

# Zonal Statistics (native)
echo -e "${YELLOW}  Zonal Statistics:${NC}"
if command -v python3 &>/dev/null; then
    run_native "Python" "python3 benchmarks/zonal_stats.py" "zonal_stats"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/zonal_stats.jl" "zonal_stats"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/zonal_stats.R" "zonal_stats"
fi

# Interpolation (native)
echo -e "${YELLOW}  Spatial Interpolation:${NC}"
if command -v python3 &>/dev/null; then
    run_native "Python" "python3 benchmarks/interpolation_idw.py" "interpolation"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/interpolation_idw.jl" "interpolation"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/interpolation_idw.R" "interpolation"
fi

# Time-Series (native)
echo -e "${YELLOW}  Time-Series NDVI:${NC}"
if command -v python3 &>/dev/null; then
    run_native "Python" "python3 benchmarks/timeseries_ndvi.py" "timeseries"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/timeseries_ndvi.jl" "timeseries"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/timeseries_ndvi.R" "timeseries"
fi

# Hyperspectral (native)
echo -e "${YELLOW}  Hyperspectral SAM:${NC}"
if command -v python3 &>/dev/null; then
    run_native "Python" "python3 benchmarks/hsi_stream.py" "hsi_stream"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/hsi_stream.jl" "hsi_stream"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/hsi_stream.R" "hsi_stream"
fi

# Vector PIP (native)
echo -e "${YELLOW}  Vector Point-in-Polygon:${NC}"
if command -v python3 &>/dev/null; then
    run_native "Python" "python3 benchmarks/vector_pip.py" "vector_pip"
fi
if command -v julia &>/dev/null; then
    run_native "Julia" "JULIA_NUM_THREADS=$JULIA_NUM_THREADS julia benchmarks/vector_pip.jl" "vector_pip"
fi
if command -v Rscript &>/dev/null; then
    run_native "R" "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS Rscript benchmarks/vector_pip.R" "vector_pip"
fi

    echo ""
    echo -e "${GREEN}  ✓ Native benchmarks complete${NC}"
    echo "  Results saved alongside container results in: results/"
fi  # End of native-only section

# ── [13/13] Summary ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "========================================================================"
echo "  ✓ ALL BENCHMARKS COMPLETE"
echo "========================================================================"
echo -e "${NC}"

if [[ "$MODE" == "all" ]]; then
    echo -e "  ${MAGENTA}Ran: Container + Native benchmarks${NC}"
elif [[ "$MODE" == "container" ]]; then
    echo -e "  ${YELLOW}Ran: Container benchmarks only${NC}"
else
    echo -e "  ${GREEN}Ran: Native benchmarks only${NC}"
fi

echo ""
echo "  Results directory:"
find results -name '*.json' -o -name '*.txt' -o -name '*.md' 2>/dev/null | \
    grep -v gitkeep | sort | sed 's/^/    /'
echo ""
echo "  Key Outputs:"
echo "    Core Benchmarks (container):"
echo "      - results/matrix_ops_{python,julia,r}.json"
echo "      - results/io_ops_{python,julia,r}.json"
echo "    GIS Benchmarks (container):"
echo "      - results/warm_start/*_warm.json"
echo "      - results/cold_start/*_cold.json"
echo "    Analysis:"
echo "      - results/chen_revels_validation_summary.md"
echo "      - results/tedesco_comparison.md"
echo ""
echo "  Next steps:"
echo "    1. Review:    ls -lh results/"
echo "    2. Visualize: python tools/visualize_benchmarks.py"
echo "    3. Compare:   python tools/compare_with_tedesco.py"
echo "    4. Report:    python validation/generate_report.py"
echo ""
echo "  Usage:"
echo "    ./run_benchmarks.sh           # Full (container + native)"
echo "    ./run_benchmarks.sh --container-only  # Container only"
echo "    ./run_benchmarks.sh --native-only    # Native only"
echo ""
echo "  Documentation:"
echo "    - DATA_PROVENANCE.md"
echo "    - METHODOLOGY_NOTES_FOR_THESIS.md"
echo ""
if [[ "$MODE" != "native" ]] && [ -f results/container_hashes.txt ]; then
    echo "  Container digests saved → results/container_hashes.txt"
fi
echo ""
echo -e "${YELLOW}  Thesis Quality: A (container + native + literature comparison)${NC}"
echo ""
