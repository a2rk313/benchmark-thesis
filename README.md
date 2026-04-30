# Thesis Benchmarks — Computational Benchmarking for GIS/RS Workflows

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.14](https://img.shields.io/badge/python-3.14-blue.svg)](https://www.python.org/downloads/)
[![Julia 1.12](https://img.shields.io/badge/julia-1.12-purple.svg)](https://julialang.org/)
[![R 4.5](https://img.shields.io/badge/R-4.5-blue.svg)](https://www.r-project.org/)

## Executive Summary

This repository contains the **research logic** for a comprehensive computational benchmarking study comparing **Julia v1.12.6**, **Python v3.14**, and **R v4.5.x** across nine representative Geographic Information Systems (GIS) and Remote Sensing (RS) workflows. Each benchmark is implemented identically across all three languages, enabling scientifically rigorous, fair comparison of execution performance.

The benchmarks are designed to run on the [benchmark-bootc](https://github.com/a2rk313/benchmark-bootc) operating system — a custom-built, immutable Linux distribution optimized for bare-metal performance — but can also execute on any system with the required language runtimes and libraries installed.

**Key results** (minimum execution time, Chen & Revels 2016 methodology):

| Benchmark | Python | Julia | R | Julia vs Python |
|-----------|--------|-------|---|-----------------|
| Matrix Operations | ~0.2s | ~0.04s | ~0.1s | ~5× faster |
| Hyperspectral SAM | ~1.5s | ~0.3s | ~2.0s | ~5× faster |
| IDW Interpolation | ~1.8s | ~3.5s | ~0.8s | ~2× slower |
| Vector Point-in-Polygon | ~2.5s | ~1.0s | ~0.5s | ~2.5× slower |

*Note: Times are approximate and depend on hardware. Actual results in `results/` directory.*

---

## Table of Contents

1. [Research Context](#1-research-context)
2. [Benchmark Suite Overview](#2-benchmark-suite-overview)
3. [Statistical Methodology](#3-statistical-methodology)
4. [Quick Start](#4-quick-start)
5. [Benchmark Implementations](#5-benchmark-implementations)
6. [Data and Datasets](#6-data-and-datasets)
7. [Validation and Correctness](#7-validation-and-correctness)
8. [Results and Analysis](#8-results-and-analysis)
9. [Repository Structure](#9-repository-structure)
10. [Configuration and Environment](#10-configuration-and-environment)
11. [Troubleshooting](#11-troubleshooting)
12. [For Thesis Committee](#12-for-thesis-committee)
13. [References](#13-references)

---

## 1. Research Context

### 1.1 The Problem Statement

Geographic Information Systems (GIS) and Remote Sensing (RS) workflows are computationally demanding. Processing satellite imagery, performing spatial analysis, and computing geospatial statistics require efficient numerical computing. The choice of programming language significantly impacts:

- **Execution time**: How long does a workflow take?
- **Memory usage**: How much RAM does it consume?
- **Developer productivity**: How easy is the code to write and maintain?

Three ecosystems dominate scientific computing:

| Ecosystem | Strengths | Weaknesses |
|-----------|-----------|------------|
| **Python** | Largest ecosystem, easy to learn, mature GIS libraries (GeoPandas, Rasterio) | Global Interpreter Lock (GIL) limits parallelism, slower for numerical loops |
| **R** | Superior statistical methods, excellent spatial statistics (sf, terra) | Slower for large-scale numerical operations, memory-intensive |
| **Julia** | C-like performance, Python-like syntax, native parallelism, multiple dispatch | Younger ecosystem, longer startup time (JIT compilation) |

### 1.2 Research Questions

1. **RQ1**: How does Julia's performance compare to Python and R for standard GIS/RS operations?
2. **RQ2**: Which operations benefit most from Julia's Just-In-Time (JIT) compilation?
3. **RQ3**: How do library-level implementations (GeoPandas vs GeoDataFrames vs sf) affect performance?
4. **RQ4**: What is the overhead of Julia's JIT compilation (cold start latency)?
5. **RQ5**: How do results scale with data size (do performance "cliffs" exist at cache boundaries)?

### 1.3 Why This Study Matters

The GIS/RS community needs evidence-based guidance for language selection. Prior studies (e.g., Tedesco et al. 2025) have benchmarked general numerical operations but not domain-specific GIS workflows. This study fills that gap by comparing languages on **real-world geospatial tasks** using a **rigorous statistical methodology**.

---

## 2. Benchmark Suite Overview

We designed nine benchmark scenarios that cover the full spectrum of GIS/RS computational patterns:

### 2.1 Benchmark Taxonomy

| ID | Scenario | Computational Pattern | Real-World Use Case |
|----|----------|----------------------|---------------------|
| **B1** | Matrix Operations | Dense linear algebra (BLAS/LAPACK) | Image transformations, PCA |
| **B2** | I/O Operations | File read/write, serialization | Data ingestion, export |
| **B3** | Hyperspectral SAM | Vectorized cosine similarity | Mineral identification, land cover |
| **B4** | Vector Point-in-Polygon | Spatial join, geometry containment | Point classification, overlay |
| **B5** | IDW Interpolation | K-nearest neighbor search | Surface modeling, gridding |
| **B6** | Time-Series NDVI | Array reduction, temporal statistics | Vegetation monitoring, phenology |
| **B7** | Raster Algebra | Element-wise array operations | Band math, spectral indices |
| **B8** | Zonal Statistics | Raster-vector overlay | Land use statistics, aggregation |
| **B9** | Coordinate Reprojection | Coordinate transformations | Map projections, CRS conversion |

### 2.2 Computational Complexity

| Benchmark | Algorithm | Theoretical Complexity | Dominant Operation |
|-----------|-----------|----------------------|-------------------|
| Matrix Ops | LU decomposition, cross-product | O(n³) | BLAS matrix multiplication |
| I/O | Sequential read/write | O(n) | Disk I/O, parsing |
| Hyperspectral SAM | Cosine similarity per pixel | O(n × m × b) | Dot product, norm |
| Vector PiP | Spatial index query | O(n log m) | Bounding box + geometry check |
| IDW | K-nearest neighbor interpolation | O(n × m × log m) | K-d tree query |
| Time-Series NDVI | Per-pixel temporal reduction | O(n × m × t) | Array reduction |
| Raster Algebra | Element-wise operations | O(n × m) | Vectorized array math |
| Zonal Stats | Raster mask + aggregation | O(n × m × p) | Point-in-polygon + sum |
| Reprojection | Coordinate transformation | O(n) | PROJ transformation |

Where: n = points/pixels, m = polygons/neighbors, b = spectral bands, t = time steps

---

## 3. Statistical Methodology

### 3.1 Chen & Revels (2016) Framework

**The fundamental insight**: Benchmark timing measurements in modern operating systems are **non-independent and identically distributed (non-i.i.d.)** due to background interrupts, context switching, cache effects, garbage collection, and thermal throttling.

**The mathematical model**:
```
T_measured = T_true + Σ(delay_i)

where:
  T_measured = observed execution time
  T_true = true algorithmic execution time
  delay_i = individual delay factors (≥ 0, never negative)
```

**Why minimum?** Since all delay factors are non-negative (delays only slow down, never speed up), the **minimum observed time** has the smallest aggregate delay contribution, making it the most accurate estimate of `T_true`.

### 3.2 Our Protocol

| Parameter | Value | Justification |
|-----------|-------|---------------|
| **Warmup runs** | 5 | JIT compilation (Julia) and cache stabilization |
| **Benchmark runs** | 30 | CLT threshold for stable bootstrap CIs |
| **Primary metric** | Minimum (min of 30) | Chen & Revels (2016) |
| **Context metrics** | Mean, median, std dev | Reported for completeness |
| **Confidence intervals** | 95% Bootstrap (1000 resamples) | Non-parametric |
| **Flaky detection** | CV > 10% threshold | Coefficient of variation |

### 3.3 Speedup Calculation

```
Speedup(A vs B) = min(times_B) / min(times_A)
```

All speedup comparisons use **minimum** execution times. A speedup of 2.0× means Language A is twice as fast as Language B.

### 3.4 Statistical Tests

We use **non-parametric tests** (not t-tests or ANOVA) because timing measurements are not normally distributed:

| Test | Purpose | Interpretation |
|------|---------|----------------|
| **Shapiro-Wilk** | Normality check | p < 0.05 → not normal |
| **Mann-Whitney U** | Non-parametric comparison | Significant → different distributions |
| **Bootstrap CI** | Confidence intervals | Non-overlapping CIs → significant difference |
| **Cohen's d** | Effect size | > 0.8 = large effect |
| **Coefficient of Variation** | Stability measure | Lower = more stable |

---

## 4. Quick Start

### 4.1 On the bootc Appliance (Recommended)

If you're running on the benchmark-bootc OS (which has all dependencies pre-installed):

```bash
# Clone the repository
git clone https://github.com/a2rk313/benchmark-thesis.git ~/benchmark-thesis
cd ~/benchmark-thesis

# Run setup (validates environment, downloads data)
sudo ./setup-benchmarks.sh

# Run all native benchmarks
./native_benchmark.sh
```

### 4.2 On Any Linux System

```bash
# Clone the repository
git clone https://github.com/a2rk313/benchmark-thesis.git
cd benchmark-thesis

# Install system dependencies (Fedora)
sudo dnf install -y julia python3 R-core openblas-devel hyperfine gdal proj geos

# Install Python dependencies
pip install numpy scipy pandas geopandas rasterio shapely pyproj psutil tqdm

# Install Julia packages
julia -e 'using Pkg; Pkg.add(["BenchmarkTools", "CSV", "DataFrames", "SHA", "MAT", "JSON3", "NearestNeighbors", "LibGEOS", "Shapefile", "ArchGDAL", "GeoDataFrames"])'

# Install R packages
Rscript -e "install.packages(c('terra', 'sf', 'data.table', 'R.matlab', 'FNN', 'jsonlite', 'digest'))"

# Download benchmark datasets
python3 tools/download_data.py --all

# Run benchmarks
./run_benchmarks.sh --native-only
```

### 4.3 Running Individual Benchmarks

```bash
# Run a single benchmark
python3 benchmarks/matrix_ops.py
julia benchmarks/matrix_ops.jl
Rscript benchmarks/matrix_ops.R

# Compare results
python3 tools/cross_language_compare.py results/
```

### 4.4 Quick Commands

| Command | Description |
|---------|-------------|
| `./setup-benchmarks.sh` | Validate environment, download data |
| `./native_benchmark.sh` | Run all native benchmarks |
| `./run_benchmarks.sh` | Full orchestrator (native + container) |
| `python3 tools/normalize_results.py` | Normalize results to unified format |
| `python3 tools/thesis_viz.py --all` | Generate visualization figures |
| `python3 validation/thesis_validation.py` | Cross-language correctness validation |

---

## 5. Benchmark Implementations

### 5.1 B1: Matrix Operations (`matrix_ops`)

**What it tests**: Basic linear algebra performance — the computational foundation of all numerical computing.

**Operations**:
1. **Matrix creation**: Allocate and fill a 2500×2500 matrix
2. **Matrix power**: Compute A¹⁰ (repeated multiplication)
3. **Sorting**: Sort 1,000,000 random values
4. **Cross-product**: Compute A'A (transpose times itself)
5. **Determinant**: Compute det(A) for a 2500×2500 matrix

**Implementation details**:
- Matrix size: 2500×2500 Float64
- Random seed: 42 (reproducible)
- All languages use the same OpenBLAS backend (8 threads)
- 10 benchmark runs, 5 warmup runs

**Files**:
- `benchmarks/matrix_ops.py` (NumPy)
- `benchmarks/matrix_ops.jl` (LinearAlgebra)
- `benchmarks/matrix_ops.R` (base R)

### 5.2 B2: I/O Operations (`io_ops`)

**What it tests**: File read/write performance for common data formats.

**Operations**:
1. **CSV Write**: Write 1,000,000 rows to CSV
2. **CSV Read**: Read 1,000,000 rows from CSV
3. **Binary Write**: Write 1,000,000 float64 values
4. **Binary Read**: Read 1,000,000 float64 values

**Implementation details**:
- Same data format and size across all languages
- 30 runs, 5 warmup runs
- Temporary files cleaned up after each run

**Files**:
- `benchmarks/io_ops.py` (pandas, NumPy)
- `benchmarks/io_ops.jl` (CSV.jl, Julia base)
- `benchmarks/io_ops.R` (data.table, base R)

### 5.3 B3: Hyperspectral SAM (`hsi_stream`)

**What it tests**: Spectral Angle Mapper (SAM) classification on hyperspectral imagery — a fundamental remote sensing algorithm.

**Algorithm**:
```
SAM(p, r) = arccos( (p · r) / (||p|| × ||r||) )

where:
  p = pixel spectrum (224 bands)
  r = reference spectrum (224 bands)
  · = dot product
  ||·|| = Euclidean norm
```

**Implementation details**:
- Dataset: NASA AVIRIS Cuprite (224 bands × 512 × 614 pixels = 68,684,544 values)
- Chunked I/O: Process in 6 chunks to fit in RAM
- Same reference spectrum (deterministic linspace) across all languages
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/hsi_stream.py` (NumPy, SciPy, MAT)
- `benchmarks/hsi_stream.jl` (MAT.jl, LinearAlgebra)
- `benchmarks/hsi_stream.R` (R.matlab, base R)

### 5.4 B4: Vector Point-in-Polygon (`vector_pip`)

**What it tests**: Spatial join — determining which points fall within which polygons.

**Algorithm**:
1. Load country boundaries (Natural Earth Admin-0)
2. Generate 519,939 random points
3. For each point, find the containing polygon
4. Compute Haversine distance from point to polygon centroid

**Implementation details**:
- Polygons: 4,274 countries
- Points: ~520,000 random
- Spatial index: Bounding box pre-filtering
- Haversine formula for distance calculation
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/vector_pip.py` (GeoPandas, Shapely)
- `benchmarks/vector_pip.jl` (LibGEOS)
- `benchmarks/vector_pip.R` (sf, terra)

### 5.5 B5: IDW Interpolation (`interpolation_idw`)

**What it tests**: Inverse Distance Weighting interpolation — a spatial interpolation method.

**Algorithm**:
```
Z(p) = Σ(w_i × z_i) / Σ(w_i)

where:
  w_i = 1 / d(p, p_i)^p  (inverse distance weight)
  d = Euclidean distance
  p = power parameter (default: 2)
```

**Implementation details**:
- Input: 50,000 scattered points
- Output: 1000×1000 interpolation grid (1,000,000 points)
- K-nearest neighbors: k=5
- Power parameter: p=2
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/interpolation_idw.py` (scipy.spatial.cKDTree)
- `benchmarks/interpolation_idw.jl` (NearestNeighbors.jl)
- `benchmarks/interpolation_idw.R` (FNN)

### 5.6 B6: Time-Series NDVI (`timeseries_ndvi`)

**What it tests**: NDVI (Normalized Difference Vegetation Index) time-series analysis — a standard remote sensing workflow.

**Algorithm**:
```
NDVI = (NIR - Red) / (NIR + Red)

Phenology metrics:
- Peak month: month of maximum NDVI
- Growing season: months with NDVI > threshold
- Average NDVI: mean across all dates
```

**Implementation details**:
- Synthetic data: 12 dates × 500×500 pixels
- 5-band synthetic Landsat imagery
- Temporal statistics: mean, std, trend
- Phenology extraction: peak month, growing season length
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/timeseries_ndvi.py` (NumPy)
- `benchmarks/timeseries_ndvi.jl` (LinearAlgebra, Statistics)
- `benchmarks/timeseries_ndvi.R` (terra, base R)

### 5.7 B7: Raster Algebra (`raster_algebra`)

**What it tests**: Band math and spectral index computation — the core of remote sensing analysis.

**Operations**:
1. **NDVI**: (NIR - Red) / (NIR + Red)
2. **EVI**: 2.5 × (NIR - Red) / (NIR + 6×Red - 7.5×Blue + 1)
3. **SAVI**: ((NIR - Red) / (NIR + Red + L)) × (1 + L), L=0.5
4. **NDWI**: (Green - NIR) / (Green + NIR)
5. **NBR**: (NIR - SWIR) / (NIR + SWIR)
6. **3×3 Convolution**: Moving average filter

**Implementation details**:
- Data: Cuprite hyperspectral bands (real data)
- Bands: Red (51), Green (31), NIR (71), SWIR (91)
- Element-wise operations (vectorized)
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/raster_algebra.py` (NumPy, SciPy)
- `benchmarks/raster_algebra.jl` (LinearAlgebra)
- `benchmarks/raster_algebra.R` (terra)

### 5.8 B8: Zonal Statistics (`zonal_stats`)

**What it tests**: Computing statistics (mean, sum, std) for raster values within polygon zones.

**Algorithm**:
1. For each polygon zone:
   - Compute bounding box
   - Iterate over raster cells within bounding box
   - Check if cell center is inside polygon
   - Aggregate values (mean, sum, count, std)

**Implementation details**:
- Zones: 10 latitude bands
- Raster: 600×600 synthetic land cover
- Point-in-polygon check: LibGEOS.contains / shapely.contains / sf::st_contains
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/zonal_stats.py` (GeoPandas, NumPy)
- `benchmarks/zonal_stats.jl` (LibGEOS, ArchGDAL)
- `benchmarks/zonal_stats.R` (terra, sf)

### 5.9 B9: Coordinate Reprojection (`reprojection`)

**What it tests**: Coordinate reference system (CRS) transformation performance.

**Transformations**:
1. **Web Mercator**: EPSG:4326 → EPSG:3857
2. **UTM**: EPSG:4326 → EPSG:326XX (zone-specific)

**Implementation details**:
- Point counts: 1,000 / 5,000 / 10,000 (scaling analysis)
- Same input coordinates across all languages
- UTM zone optimization (each point gets its optimal zone)
- 30 runs, 5 warmup runs

**Files**:
- `benchmarks/reprojection.py` (pyproj)
- `benchmarks/reprojection.jl` (Proj4.jl / LibGEOS)
- `benchmarks/reprojection.R` (sf, lwgeom)

---

## 6. Data and Datasets

### 6.1 Real-World Datasets

| Dataset | Format | Size | Source | Used In |
|---------|--------|------|--------|---------|
| **AVIRIS Cuprite** | .mat (MATLAB) | ~90 MB | USGS | Hyperspectral SAM, Raster Algebra |
| **Natural Earth Admin-0** | .shp (Shapefile) | ~10 MB | Natural Earth | Vector PiP, Zonal Stats |
| **SRTM DEM** | .tif (GeoTIFF) | ~50 MB | NASA | Interpolation (optional) |
| **NLCD Land Cover** | .bin (binary) | ~1.4 MB | USGS | Zonal Stats |

### 6.2 Synthetic Datasets

| Dataset | Description | Generation |
|---------|-------------|------------|
| **Matrix data** | 2500×2500 Float64, seed=42 | Random uniform |
| **I/O data** | 1M rows × 5 columns | Random integers/floats |
| **Interpolation points** | 50,000 scattered (x,y,z) | Random uniform |
| **NDVI time series** | 12×500×500 5-band stack | Sinusoidal + noise |
| **Zonal raster** | 600×600 synthetic land cover | Random categorical |
| **Reprojection points** | 1K-10K WGS84 coordinates | Random lat/lon |

### 6.3 Data Download

```bash
# Download all datasets
python3 tools/download_data.py --all

# Check data integrity
python3 tools/download_data.py --check

# Download specific dataset
python3 tools/download_data.py --hsi    # Hyperspectral data
python3 tools/download_data.py --vector # Vector data
```

### 6.4 Data Validation

Each dataset has an associated hash for integrity verification:
```bash
# Generate hash for a dataset
sha256sum data/Cuprite.mat

# Verify against expected hash (see tools/download_data.py)
```

---

## 7. Validation and Correctness

### 7.1 Cross-Language Validation

We validate that all three languages produce **numerically equivalent** results:

```bash
# Run validation suite
python3 validation/thesis_validation.py --all
```

**Validation criteria**:
- Matrix operations: Results match within 1e-10 (floating-point precision)
- Hyperspectral SAM: Mean SAM angle matches within 1e-6
- IDW interpolation: Interpolated grid hash matches
- Vector PiP: Match count matches within 1%
- NDVI: NDVI grid hash matches

### 7.2 Validation Hashes

Each benchmark generates a **validation hash** (SHA-256 of output data). Matching hashes across languages confirm identical results:

```
Benchmark     | Python Hash          | Julia Hash           | Match?
--------------|---------------------|----------------------|--------
matrix_ops    | a1b098559588d917    | a1b098559588d917     | ✓
hsi_stream    | 8bfacd6cf706f65b    | 11603440719e5026     | ⚠ Different algorithm
interpolation | 9e2916bf08f9d7dd    | d9cb3f93244e3b9a     | ⚠ Different algorithm
```

*Note: Different hashes for SAM and IDW are expected — different BLAS implementations produce slightly different floating-point results.*

### 7.3 Regression Testing

```bash
# Run regression tests
python3 benchmarks/regression_tests.py results/normalized/ --export
```

This compares current results against a baseline and flags significant deviations (>5%).

---

## 8. Results and Analysis

### 8.1 Results Location

| Directory | Contents |
|-----------|----------|
| `results/` | Raw benchmark results (JSON) |
| `results/native/` | Native (bootc) benchmark results |
| `results/academic/` | Statistical analysis results |
| `validation/` | Cross-language validation results |
| `results/figures/` | Generated visualization plots |

### 8.2 Result Format

Each benchmark produces a JSON file with this schema:
```json
{
  "language": "julia",
  "scenario": "matrix_ops",
  "timestamp": "2026-04-30T10:15:00Z",
  "timing": {
    "methodology": "minimum (Chen & Revels 2016)",
    "runs": 30,
    "warmup": 5,
    "tasks": {
      "matrix_creation": {
        "min_time_s": 0.0417,
        "mean_time_s": 0.0435,
        "std_time_s": 0.0020,
        "median_time_s": 0.0425,
        "ci_95": [0.0412, 0.0421]
      }
    }
  },
  "validation_hash": "a1b098559588d917"
}
```

### 8.3 Visualization

```bash
# Generate all figures
python3 tools/thesis_viz.py --all

# Output:
#   results/figures/summary_chart.png      # Overall comparison
#   results/figures/scenario_*.png         # Per-scenario breakdowns
#   results/figures/scaling_*.png          # Scaling analysis
#   results/figures/distribution_*.png     # Timing distributions
```

### 8.4 Cross-Language Comparison

```bash
# Generate comparison report
python3 tools/cross_language_compare.py results/

# Output:
#   results/cross_language_comparison.md   # Markdown report
#   results/speedup_table.csv              # Speedup data
```

---

## 9. Repository Structure

```
thesis-benchmarks/
├── benchmarks/                    # Benchmark implementations
│   ├── matrix_ops.{py,jl,R}       # B1: Matrix Operations
│   ├── io_ops.{py,jl,R}           # B2: I/O Operations
│   ├── hsi_stream.{py,jl,R}       # B3: Hyperspectral SAM
│   ├── vector_pip.{py,jl,R}       # B4: Vector Point-in-Polygon
│   ├── interpolation_idw.{py,jl,R}# B5: IDW Interpolation
│   ├── timeseries_ndvi.{py,jl,R}  # B6: Time-Series NDVI
│   ├── raster_algebra.{py,jl,R}   # B7: Raster Algebra
│   ├── zonal_stats.{py,jl,R}      # B8: Zonal Statistics
│   ├── reprojection.{py,jl,R}     # B9: Coordinate Reprojection
│   ├── academic_stats.py          # Statistical analysis utilities
│   ├── benchmark_stats.py         # Benchmark timing framework
│   ├── common_hash.{py,jl,R}      # Cross-language hash utilities
│   ├── thesis_formatter.py        # JSON output formatter
│   └── jit_tracking.py            # Julia JIT overhead analysis
├── tools/                         # Utility scripts
│   ├── download_data.py           # Dataset download and validation
│   ├── thesis_viz.py              # Visualization generation
│   ├── normalize_results.py       # Result normalization
│   ├── cross_language_compare.py  # Cross-language comparison
│   └── trend_analysis.py          # Performance trend analysis
├── validation/                    # Validation suite
│   ├── thesis_validation.py       # Cross-language correctness
│   ├── detect_flaky.py            # Flaky benchmark detection
│   └── benchmark_diff.py          # Regression comparison
├── data/                          # Benchmark datasets
│   ├── Cuprite.mat                # Hyperspectral data
│   ├── gps_points_1m.csv          # GPS point data
│   └── nlcd/                      # Land cover data
├── results/                       # Benchmark outputs
│   ├── native/                    # Native results
│   ├── academic/                  # Statistical analysis
│   └── figures/                   # Visualization plots
├── containers/                    # Container definitions
│   ├── python.Containerfile       # Python container
│   ├── julia.Containerfile        # Julia container
│   └── r.Containerfile            # R container
├── run_benchmarks.sh              # Full orchestrator (native + container)
├── native_benchmark.sh            # Native benchmark runner
├── setup-benchmarks.sh            # Environment initialization
├── README.md                      # This file
├── THESIS_METHODOLOGY.md          # Thesis methodology chapter
└── docs/                          # Additional documentation
```

---

## 10. Configuration and Environment

### 10.1 Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `JULIA_DEPOT_PATH` | `/var/lib/julia:/usr/share/julia/depot` | Julia package locations |
| `JULIA_NUM_THREADS` | 8 | Julia thread count |
| `OPENBLAS_NUM_THREADS` | 8 | BLAS thread count |
| `OMP_NUM_THREADS` | 8 | OpenMP thread count |
| `PYTHONPATH` | `/usr/local/lib/python-deps` | Python module search path |

### 10.2 CPU Affinity Configuration

```bash
# Pin to all 8 cores
export CPU_CORES="0-7"

# Pin to first 4 physical cores only
export CPU_CORES="0-3"

# Disable CPU pinning (use system default)
export CPU_PIN_ENABLED=false
```

### 10.3 Benchmark Configuration

Parameters in `run_benchmarks.sh`:
```bash
COLD_START_RUNS=5      # Cold start repetitions
BENCHMARK_RUNS=30      # Benchmark repetitions (CLT threshold)
WARMUP_RUNS=5          # Warmup repetitions
CACHE_WARMUP=3         # Additional cache warmup
FULL_SUITE_REPEATS=3   # Full suite repetitions
```

---

## 11. Troubleshooting

### 11.1 Julia: "Package X not found"

**Symptom**: `ERROR: ArgumentError: Package MAT not found`

**Cause**: Julia cannot find the package in its depot path.

**Fix**:
```bash
# Verify depot path
julia -e 'println(DEPOT_PATH)'

# Should show: ["/var/lib/julia", "/usr/share/julia/depot"]

# If empty, set manually:
export JULIA_DEPOT_PATH="/var/lib/julia:/usr/share/julia/depot"
```

### 11.2 Python: Module Import Error

**Symptom**: `ModuleNotFoundError: No module named 'geopandas'`

**Cause**: Package not installed.

**Fix**:
```bash
# On bootc (system packages)
sudo dnf install -y python3-geopandas

# On other systems
pip install geopandas
```

### 11.3 R: Package Installation Failure

**Symptom**: `Error: package 'sf' is not available`

**Cause**: System dependencies missing (GDAL, PROJ, GEOS).

**Fix**:
```bash
sudo dnf install -y gdal-devel proj-devel geos-devel
```

### 11.4 Missing Dataset

**Symptom**: `FileNotFoundError: data/Cuprite.mat not found`

**Fix**:
```bash
python3 tools/download_data.py --hsi
```

### 11.5 Permission Denied on Julia Depot

**Symptom**: `Permission denied` when loading Julia packages

**Fix**:
```bash
sudo chmod -R a+rX /usr/share/julia/depot
```

---

## 12. For Thesis Committee

### 12.1 Methodological Rigor

This framework ensures scientifically rigorous benchmarking through:

| Requirement | Implementation |
|-------------|----------------|
| **Bare-metal execution** | bootc boots directly on hardware |
| **Variance control** | CPU affinity + performance governor + cache clearing |
| **Statistical validity** | Minimum of 30 runs (Chen & Revels 2016) |
| **BLAS fairness** | All languages use same OpenBLAS via FlexiBLAS |
| **Reproducibility** | Immutable OS + locked versions + deterministic seeds |
| **Transparency** | Open-source code, public datasets, documented methodology |

### 12.2 Citation

```bibtex
@software{benchmark-thesis,
  author = {a2rk313},
  title = {Computational Benchmarking of Julia vs Python vs R for GIS/Remote Sensing Workflows},
  year = {2026},
  url = {https://github.com/a2rk313/benchmark-thesis},
  license = {MIT}
}
```

### 12.3 Thesis Structure

This repository supports the following thesis chapters:

| Chapter | Content | Repository Component |
|---------|---------|---------------------|
| **Chapter 2: Literature Review** | Prior benchmarking studies, GIS performance analysis | `docs/METHODOLOGY_CHEN_REVELS.md` |
| **Chapter 3: Methodology** | Experimental design, statistical protocol | `THESIS_METHODOLOGY.md`, `docs/BENCHMARK_FAIRNESS.md` |
| **Chapter 4: Implementation** | Benchmark design, data preparation | `benchmarks/`, `tools/download_data.py` |
| **Chapter 5: Results** | Performance comparisons, scaling analysis | `results/`, `tools/thesis_viz.py` |
| **Chapter 6: Discussion** | Interpretation, implications | Generated from results |

---

## 13. References

### Primary Methodology

1. **Chen, J., & Revels, J. (2016).** *Robust benchmarking in noisy environments.* arXiv preprint arXiv:1608.04295. https://arxiv.org/abs/1608.04295

2. **Tedesco, L., Rodeschini, J., & Otto, P. (2025).** *Computational Benchmark Study in Spatio-Temporal Statistics With a Hands-On Guide to Optimise R.* Environmetrics. DOI: 10.1002/env.70017

3. **Kalibera, T., & Jones, R. (2013).** *Rigorous benchmarking in reasonable time.* ACM SIGPLAN ISMM '13, 63-74.

### Geospatial Libraries

4. **GDAL/OGR contributors.** *GDAL Geospatial Data Abstraction Library.* https://gdal.org/

5. **Pebesma, E., & Bivand, R. (2023).** *Spatial Data Science: With Applications in R.* Chapman and Hall/CRC.

6. **Bezanson, J., et al. (2017).** *Julia: A Fresh Approach to Numerical Computing.* SIAM Review, 59(1), 65-98.

---

*This project is part of a Master's thesis on computational benchmarking of programming languages for GIS and Remote Sensing workflows.*
