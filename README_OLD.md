# Computational Benchmarking Suite: Julia vs Python vs R for GIS/RS

## Overview

This repository contains a **publication-ready** benchmarking suite for evaluating Julia, Python, and R performance in geospatial computing workflows. The implementation follows the **Chen & Revels (2016)** robust benchmarking methodology and validates findings from **Tedesco et al. (2025)**.

### Key Features

✅ **Methodologically Rigorous**: Implements Chen & Revels (2016) robust benchmarking  
✅ **Literature-Validated**: Direct comparison with Tedesco et al. (2025)  
✅ **Reproducible**: Exact version pinning, containerized environments, SHA-256 checksums  
✅ **Comprehensive**: 14 benchmarks (GIS-specific + core computational)  
✅ **Real-world Data**: Natural Earth countries, AVIRIS hyperspectral imagery  
✅ **Statistical Validation**: Empirical validation of methodology principles

### NEW in Version 3.0 (March 2026)

🆕 **Matrix Operations Benchmarks** - Enable Tedesco et al. (2025) comparison  
🆕 **I/O Operations Benchmarks** - Demonstrate Julia's I/O advantages  
🆕 **Chen & Revels Methodology** - Mathematically justified minimum estimator  
🆕 **Complete Data Provenance** - Full documentation of all data sources  
🆕 **Validation Suite** - Empirical validation of benchmarking principles  
🆕 **Literature Comparison Tools** - Automated comparison with published results

### Quick Links

📖 **[IMPROVEMENTS_SUMMARY.md](IMPROVEMENTS_SUMMARY.md)** - What's new in v3.0  
📖 **[METHODOLOGY_CHEN_REVELS.md](METHODOLOGY_CHEN_REVELS.md)** - Statistical methodology  
📖 **[DATA_PROVENANCE.md](DATA_PROVENANCE.md)** - Complete data documentation  

---

## Directory Structure

```
thesis-benchmarks/
├── containers/              # OCI containerfiles (Fedora 43 base)
│   ├── python.Containerfile # Python 3.14 + geospatial stack
│   ├── julia.Containerfile  # Julia 1.12 + packages
│   └── r.Containerfile      # R 4.5 + terra/sf
│
├── benchmarks/              # Benchmark implementations
│   ├── vector_pip.py        # Python: Point-in-Polygon + Haversine
│   ├── vector_pip.jl        # Julia: Point-in-Polygon + Haversine
│   ├── vector_pip.R         # R: Point-in-Polygon + Haversine
│   ├── hsi_stream.py        # Python: Hyperspectral SAM
│   ├── hsi_stream.jl        # Julia: Hyperspectral SAM
│   └── hsi_stream.R         # R: Hyperspectral SAM
│
├── tools/                   # Data preparation scripts
│   ├── gen_vector_data.py   # Download Natural Earth + Generate GPS points
│   └── download_hsi.py      # Download AVIRIS Jasper Ridge
│
├── validation/              # Results validation
│   └── validate_results.py  # Cross-language correctness checker
│
├── results/                 # Generated during benchmark runs
│   ├── cold_start/          # First-run latency (development)
│   ├── warm_start/          # Steady-state performance (production)
│   ├── memory/              # Memory profiling outputs
│   └── container_hashes.txt # Container SHA-256 checksums
│
├── data/                    # Generated during data prep
│   ├── natural_earth_countries.gpkg  # Complex country polygons
│   ├── gps_points_1m.csv             # 1 million GPS points
│   └── jasperRidge2_R198/            # Hyperspectral data
│
└── run_benchmarks.sh        # Master orchestrator script
```

---

## Prerequisites

### System Requirements

- **OS**: Linux (tested on Fedora 43, should work on Ubuntu 22.04+)
- **CPU**: Multi-core x86-64 processor (for parallel benchmarks)
- **RAM**: Minimum 16 GB (hyperspectral benchmark is memory-intensive)
- **Disk**: ~20 GB free space (containers + data)

### Software Dependencies

```bash
# Container runtime
sudo dnf install podman  # Fedora/RHEL
# OR
sudo apt install podman  # Ubuntu/Debian

# Benchmarking tool
cargo install hyperfine  # Requires Rust toolchain
# OR download binary from: https://github.com/sharkdp/hyperfine/releases

# Optional: For perf profiling
sudo dnf install perf sysstat
```

---

## Quick Start

### 1. Clone Repository

```bash
git clone <your-repo-url> thesis-benchmarks
cd thesis-benchmarks
chmod +x run_benchmarks.sh
```

### 2. Run Complete Benchmark Suite

```bash
./run_benchmarks.sh
```

**What this does:**
1. Builds 3 containers (Python, Julia, R) - ~10 minutes first time
2. Downloads Natural Earth countries - ~5 MB
3. Generates 1M synthetic GPS points - ~30 MB
4. Downloads AVIRIS Jasper Ridge - ~100 MB
5. Runs cold start benchmarks (5 runs each)
6. Runs warm start benchmarks (10 runs each with 3 warmup)
7. Profiles memory usage
8. Validates cross-language correctness

**Total runtime**: 30-60 minutes depending on hardware

---

## Detailed Usage

### Building Containers Individually

```bash
# Python 3.14
podman build -t thesis-python:3.13 -f containers/python.Containerfile .

# Julia 1.12
podman build -t thesis-julia:1.11 -f containers/julia.Containerfile .

# R 4.5
podman build -t thesis-r:4.5 -f containers/r.Containerfile .
```

### Running Individual Benchmarks

**Vector benchmark (warm start, Python):**
```bash
podman run --rm -v $(pwd):/benchmarks thesis-python:3.13 \
    hyperfine --warmup 3 --runs 10 \
    --export-json results/vector_python.json \
    "python3 benchmarks/vector_pip.py"
```

**Raster benchmark (cold start, Julia):**
```bash
podman run --rm  -v $(pwd):/benchmarks thesis-julia:1.11 \
    hyperfine --warmup 0 --runs 5 \
    --prepare "sync" \
    --export-json results/raster_julia_cold.json \
    "julia -t auto benchmarks/hsi_stream.jl"
```

### Memory Profiling

```bash
podman run --rm -v $(pwd):/benchmarks thesis-python:3.13 \
    /usr/bin/time -v python3 benchmarks/vector_pip.py \
    2>&1 | tee memory_python.txt
```

Key metrics in output:
- `Maximum resident set size` - Peak RAM usage (KB)
- `Major page faults` - Disk I/O events
- `Minor page faults` - In-memory page faults

### CPU Profiling (Optional)

Requires `perf` and `` container:

```bash
podman run --rm  -v $(pwd):/benchmarks thesis-julia:1.11 \
    perf stat -e cycles,instructions,cache-misses,cache-references \
    julia -t auto benchmarks/vector_pip.jl
```

---

## Benchmark Scenarios

### Scenario B: Vector Operations (Point-in-Polygon + Distance)

**Dataset:**
- **Polygons**: Natural Earth Admin-0 Countries (1:10m resolution)
  - 242 features after exploding multipolygons
  - High vertex complexity (Norway: 50K+ vertices, Indonesia: islands)
- **Points**: 1,000,000 GPS coordinates (global distribution)

**Algorithm:**
1. Spatial join using GEOS topology engine (R-tree index + exact test)
2. For each match: Calculate Haversine distance to country centroid
3. Stress test: Complex polygon topology, trigonometric computation

**Metrics:**
- Computational throughput (points/second)
- GEOS interface overhead
- Parallelization efficiency (Julia)

---

### Scenario A.2: Raster Operations (Hyperspectral SAM)

**Dataset:**
- **Source**: NASA AVIRIS Jasper Ridge
- **Bands**: 224 (continuous 380-2500 nm)
- **Size**: ~600 MB uncompressed
- **Format**: Band Interleaved by Line (BIL)

**Algorithm (Spectral Angle Mapper):**
```
For each pixel (224-dimensional vector):
    dot_product = pixel · reference
    angle = arccos(dot / (||pixel|| × ||reference||))
```

**Stress test:**
- Non-contiguous memory access (memory striding)
- High-dimensional vector operations
- Out-of-core processing (chunked I/O)

**Metrics:**
- Effective memory bandwidth
- Cache utilization
- SIMD vectorization efficiency

---

## Results Analysis

### Viewing Benchmark Results

Results are saved as JSON files:

```bash
# Cold start results
cat results/cold_start/vector_julia_cold.json | jq '.results[0].mean'

# Warm start results
cat results/warm_start/raster_python_warm.json | jq '.results[] | {mean, stddev}'
```

### Validation

```bash
python3 validation/validate_results.py
```

This script checks:
1. **Numerical precision**: Results agree within 0.1% tolerance
2. **Output consistency**: Same number of matches/pixels processed
3. **Hash validation**: Cryptographic verification of identical outputs

**Expected output:**
```
✓ ALL VALIDATIONS PASSED
All language implementations produce consistent results.
```

---

## Reproducing Results

### Container Verification

After building, verify exact containers using SHA-256:

```bash
cat results/container_hashes.txt
```

Compare against published hashes in repository.

### Data Verification

Natural Earth download is deterministic. GPS points use `seed=42` for reproducibility.

Verify data checksums:

```bash
md5sum data/gps_points_1m.csv
# Expected: <hash from paper>
```

### Statistical Validation

All benchmarks use `hyperfine` with:
- **Cold start**: 5 runs, no warmup, cache cleared
- **Warm start**: 10 runs, 3 warmup iterations
- **Outlier detection**: Automatic via hyperfine

Coefficient of variation must be < 5% for stable results.

---

## Customization

### Changing Number of Points

Edit `tools/gen_vector_data.py`:

```python
generate_gps_points(n_points=500_000, seed=42)  # Default: 1M
```

### Adding New Languages

1. Create `containers/<language>.Containerfile`
2. Implement `benchmarks/vector_pip.<ext>` following algorithm in Python version
3. Implement `benchmarks/hsi_stream.<ext>`
4. Add to `run_benchmarks.sh`

### Platform-Specific Optimization

To enable CPU-specific optimizations (WARNING: reduces reproducibility):

**Julia:**
```dockerfile
ENV JULIA_CPU_TARGET="native"  # Default: generic
```

**Python (NumPy):**
```dockerfile
RUN pip install numpy --config-settings=setup-args="-Dallow-noblas=false"
```

---

## Troubleshooting

### Container Build Failures

**Issue**: Package version conflicts  
**Fix**: Check Fedora 43 package availability:
```bash
podman run --rm fedora:43 dnf info gdal
```

**Issue**: Out of memory during build  
**Fix**: Increase podman memory limit:
```bash
podman system info | grep -A5 "memory"
```

### Benchmark Failures

**Issue**: "Cannot clear cache" warning  
**Fix**: Run with sudo (only if needed):
```bash
sudo ./run_benchmarks.sh
```

**Issue**: Hyperspectral download fails  
**Fix**: Manual download from http://www.ehu.eus/ccwintco/index.php/Hyperspectral_Remote_Sensing_Scenes

**Issue**: Julia "Out of Memory"  
**Fix**: Reduce chunk size in `benchmarks/hsi_stream.jl`:
```julia
chunk_size = 128  # Default: 256
```

### Validation Failures

**Issue**: Hashes don't match across languages  
**Explanation**: Floating-point rounding differences are acceptable if statistical measures agree within 0.1%

---

## Citation

If you use this benchmarking suite in your research, please cite:

```bibtex
@mastersthesis{your_thesis_2025,
    title={Computational Benchmarking of Julia Language against Python and R for GIS and RS Workflows},
    author={Your Name},
    year={2025},
    school={Your University}
}
```

---

## License

- **Code**: MIT License
- **Data**: CC-BY 4.0 (Natural Earth, AVIRIS datasets have separate licenses)
- **Documentation**: CC-BY 4.0

---

## Acknowledgments

- Natural Earth Data: https://www.naturalearthdata.com/
- NASA AVIRIS: https://aviris.jpl.nasa.gov/
- Hyperfine: https://github.com/sharkdp/hyperfine

---

## Contact

For questions or issues, please open a GitHub issue or contact: [your-email]

---

**Last Updated**: February 2025  
**Repository**: https://github.com/[your-username]/thesis-benchmarks  
**Documentation Version**: 1.0.0
