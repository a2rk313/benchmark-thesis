# Thesis Benchmarking Framework Architecture

## Project Overview

**Thesis Topic**: Computational Benchmarking of Julia Programming Language against Python and R for GIS and Remote Sensing Workflows

**Objective**: Evaluate Julia's performance for common GIS/Remote Sensing operations compared to established scientific computing languages (Python, R), using rigorous statistical methodology following Chen & Revels (2016) and Tedesco et al. (2025).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        THESIS BENCHMARK FRAMEWORK                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │   Python    │  │    Julia    │  │      R      │  │   Julia     │      │
│  │   3.13.12   │  │   1.11.4    │  │   4.5.3     │  │    JIT      │      │
│  │   NumPy     │  │   LinearAlg │  │   data.table │  │  Tracking   │      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘      │
│         │                │                │                │              │
│         └────────────────┴────────────────┴────────────────┘              │
│                                    │                                         │
│                          ┌─────────▼─────────┐                             │
│                          │   Benchmark Suite │                             │
│                          │  benchmark_stats  │                             │
│                          │ academic_stats    │                             │
│                          │  cross_language   │                             │
│                          └─────────┬─────────┘                             │
│                                    │                                         │
│         ┌──────────────────────────┼──────────────────────────┐            │
│         │                          │                          │            │
│  ┌──────▼──────┐          ┌──────▼──────┐          ┌──────▼──────┐     │
│  │   Results    │          │  Statistical │          │   Quality    │     │
│  │   Storage    │          │   Analysis   │          │   Assurance  │     │
│  │  results/    │          │ academic_    │          │ detect_flaky │     │
│  │  *.json      │          │ stats.py    │          │ regression_  │     │
│  └─────────────┘          └─────────────┘          │ tests.py    │     │
│                                                      └─────────────┘     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                        CI/CD Pipeline                                 │  │
│  │  GitHub Actions → mise → Benchmark Suite → Validation → Reports       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Language Stack

### Python (Primary Analysis Language)
```toml
# .mise.toml - python field
python = "3.13.12"
```
- **Role**: Primary benchmark orchestration, statistical analysis, visualization
- **Libraries**: numpy, scipy, pandas, matplotlib, seaborn, rasterio, geopandas, scikit-learn
- **Backend**: uv (fast Python installer)

### Julia (Target of Benchmarking)
```toml
# .mise.toml - julia field
julia = "1.11.4"
```
- **Role**: Target language being evaluated for GIS/RS performance
- **Key Libraries**: LinearAlgebra, BenchmarkTools, ArchGDAL, GeoDataFrames, CSV, DataFrames
- **Configuration**: `JULIA_NUM_THREADS=8` for parallel operations

### R (Established Baseline)
```toml
# .mise.toml - r field
r = "4.5.3"
```
- **Role**: Established scientific computing baseline
- **Key Libraries**: data.table, sf, stars, raster, terra
- **Configuration**: `OPENBLAS_NUM_THREADS=8`

---

## Benchmark Scenarios

### 1. Matrix Operations (`benchmarks/matrix_ops.{py,jl,R}`)
- Matrix multiplication (O(n³) - BLAS operations)
- Matrix decomposition (LU, QR, SVD)
- Linear system solving
- **Purpose**: Core computational baseline

### 2. I/O Operations (`benchmarks/io_ops.{py,jl,R}`)
- CSV read/write
- GeoTIFF read/write
- Shapefile operations
- **Purpose**: Data handling efficiency

### 3. Hyperspectral Analysis (`benchmarks/hsi_stream.{py,jl,R}`)
- Spectral Angle Mapper (SAM)
- AVIRIS Cuprite dataset (NASA public domain)
- **Purpose**: Domain-specific remote sensing processing

### 4. Vector Operations (`benchmarks/vector_pip.{py,jl,R}`)
- Point-in-polygon tests
- Spatial joins
- **Purpose**: Vector GIS operations

### 5. Interpolation (`benchmarks/interpolation_idw.{py,jl,R}`)
- Inverse Distance Weighting (IDW)
- Kriging (where supported)
- **Purpose**: Spatial interpolation

### 6. Time-Series NDVI (`benchmarks/timeseries_ndvi.{py,jl,R}`)
- MODIS-like NDVI processing
- Temporal smoothing
- **Purpose**: Time-series analysis

### 7. Raster Algebra (`benchmarks/raster_algebra.{py,jl,R}`)
- Band math operations
- NDVI calculation
- Zonal statistics
- **Purpose**: Raster computational tasks

### 8. Zonal Statistics (`benchmarks/zonal_stats.{py,jl,R}`)
- Zone-based aggregations
- Histogram calculations
- **Purpose**: Zonal raster analysis

### 9. Coordinate Reprojection (`benchmarks/reprojection.{py,jl,R}`)
- CRS transformation
- Coordinate conversion
- **Purpose**: Geodetic operations

---

## Statistical Methodology

### Primary Metric: Minimum Time (Chen & Revels, 2016)
```
min_time = min(t₁, t₂, ..., tₙ)
```
- Robust to outliers
- Represents best-case steady-state performance
- Follows academic best practices

### Sample Size: 30 Runs
- Based on Central Limit Theorem (n ≥ 30)
- 40% faster than n=50 while maintaining statistical validity
- Configurable via `BENCHMARK_RUNS=30`

### Warmup: 5 Runs
- JIT compilation warmup (Julia)
- Cache warmup
- GC stabilization

### Statistical Enhancements (v2.0)

| Function | Purpose |
|----------|---------|
| `median_of_means()` | Robust estimator combining mean efficiency with outlier resistance |
| `dagostino_pearson_test()` | Normality test for n ≥ 50 |
| `jarque_bera_test()` | Normality test for n ≥ 2000 |
| `cohen_d()` | Standardized effect size |
| `glass_delta()` | Effect size using control group SD |
| `bonferroni_correction()` | Multiple comparison correction |
| `benjamini_hochberg_correction()` | FDR-controlling correction |
| `bootstrap_ci()` | Non-parametric confidence intervals |
| `power_analysis_required_runs()` | Sample size planning |

---

## Data Scaling Framework

### Tedesco et al. (2025) Methodology
```python
# benchmark_scaling.py
MATRIX_SCALES = {
    'k1': 2500,   # Small (Tedesco k=1)
    'k2': 3500,   # Medium (Tedesco k=2)
    'k3': 5000,   # Large (Tedesco k=3)
    'k4': 7000    # Extra large (Tedesco k=4)
}
```

### Complexity Analysis
- Log-log regression for exponent estimation
- O(n), O(n log n), O(n²), O(n³) reference curves
- R² goodness-of-fit

---

## Quality Assurance

### Regression Testing (`regression_tests.py`)
- Hash-based correctness validation
- Timing consistency checks
- **Exit Codes**: 0=pass, 1=hash mismatch, 2=timing failure, 3=flaky

### Flaky Detection (`detect_flaky.py`)
```python
# Coefficient of Variation thresholds
CV < 5%      → Excellent
CV 5-10%    → Good (acceptable for thesis)
CV 10-20%   → Suspicious (investigate)
CV > 20%    → Flaky (do not use)
```

### Outlier Handling (`detect_outliers_iqr()`)
- IQR-based detection (1.5× standard, 3.0× extreme)
- Investigation checklist before discarding
- Report format for thesis methodology

---

## Cross-Language Compatibility

### Format Converter (`cross_language_converter.py`)
Converts Julia/R output to Python `BenchmarkResult` format:

```python
@dataclass
class BenchmarkResult:
    name: str
    language: str
    min_time: float
    mean_time: float
    std_time: float
    times: List[float]      # Individual run times
    median: float           # v2.0 addition
    memory_mb: float
    hash: str
    timestamp: str
```

### Common Hash (`benchmarks/common_hash.{py,jl,R}`)
- Shared hash utilities for cross-language validation
- Ensures identical results across languages

---

## CI/CD Pipeline

### GitHub Actions Workflow (`.github/workflows/run_benchmarks_v2.yml`)

```
┌─────────────────┐
│  workflow_dispatch │
│  or workflow_run    │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  benchmark-native        │     │  benchmark-container    │
│  ─────────────────────   │     │  ─────────────────────  │
│  • Setup mise           │     │  • Pull GHCR images     │
│  • Install deps         │     │  • Run container        │
│  • Run benchmarks       │     │    benchmarks           │
│  • Detect flaky         │     │  • Upload results       │
└────────┬────────────────┘     └────────────┬────────────┘
         │                               │
         └───────────────┬───────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ flaky-detection-    │
              │ analysis             │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ compare-to-baseline │
              │ (if ref provided)   │
              └─────────────────────┘
```

### Data Caching
```yaml
- uses: actions/cache@v4
  with:
    path: data/
    key: benchmark-data-${{ hashFiles('tools/download_data.py') }}
```

---

## Complete File Structure

```
thesis-benchmarks/
├── .github/
│   └── workflows/
│       ├── run_benchmarks_v2.yml    # CI/CD pipeline (v2.0)
│       ├── run_benchmarks.yml       # Legacy CI/CD pipeline
│       └── build.yml                 # Container build workflow
│
├── .mise.toml                        # Tool version management (mise)
│
├── benchmarks/                       # Core benchmark implementations
│   │
│   ├── # ===== PYTHON BENCHMARKS (.py) =====
│   ├── matrix_ops.py               # Matrix operations (NumPy)
│   ├── io_ops.py                   # I/O operations (CSV, GeoTIFF)
│   ├── hsi_stream.py               # Hyperspectral (Cuprite SAM)
│   ├── vector_pip.py                # Point-in-polygon tests
│   ├── interpolation_idw.py         # IDW interpolation
│   ├── timeseries_ndvi.py          # NDVI time-series
│   ├── raster_algebra.py            # Raster band math
│   ├── zonal_stats.py              # Zonal statistics
│   ├── reprojection.py             # Coordinate reprojection
│   │
│   ├── # ===== PYTHON MODULES =====
│   ├── benchmark_stats.py           # Core statistical functions (v2.0)
│   ├── academic_stats.py            # Academic result formatting
│   ├── common_hash.py               # Cross-language hash utilities
│   ├── thesis_formatter.py         # Thesis output formatter
│   ├── hardware_info.py            # Hardware information gathering
│   ├── main.py                     # Main entry point
│   │
│   ├── # ===== v2.0 QUALITY ASSURANCE =====
│   ├── test_enhancements.py         # Test suite (38 tests)
│   ├── regression_tests.py          # Hash-based regression detection
│   ├── detect_flaky.py             # Flaky test detection
│   ├── benchmark_diff.py            # Baseline comparison tool
│   ├── trend_analysis.py           # Performance trend tracking
│   ├── cross_language_converter.py  # Julia/R format converter
│   │
│   ├── # ===== v2.0 SPECIALIZED BENCHMARKS =====
│   ├── real_modis_timeseries.py     # Real NASA MODIS data
│   ├── parallel_mapreduce.py        # Parallel tile processing
│   └── jit_tracking.py             # Julia JIT tracking
│   │
│   ├── # ===== JULIA BENCHMARKS (.jl) =====
│   ├── matrix_ops.jl
│   ├── io_ops.jl
│   ├── hsi_stream.jl
│   ├── vector_pip.jl
│   ├── interpolation_idw.jl
│   ├── timeseries_ndvi.jl
│   ├── raster_algebra.jl
│   ├── zonal_stats.jl
│   ├── reprojection.jl
│   └── common_hash.jl
│   │
│   └── # ===== R BENCHMARKS (.R) =====
│       ├── matrix_ops.R
│       ├── io_ops.R
│       ├── hsi_stream.R
│       ├── vector_pip.R
│       ├── interpolation_idw.R
│       ├── timeseries_ndvi.R
│       ├── raster_algebra.R
│       ├── zonal_stats.R
│       ├── reprojection.R
│       └── common_hash.R
│
├── tools/                           # Data and visualization tools
│   ├── download_data.py             # Dataset download (main)
│   ├── download_cuprite.py         # AVIRIS Cuprite download
│   ├── download_hsi.py             # Hyperspectral download
│   ├── download_real_data.py       # Real satellite data
│   ├── generate_benchmark_data.py  # Synthetic data generation
│   ├── gen_vector_data.py          # Vector test data
│   ├── thesis_viz.py               # Thesis visualizations
│   ├── scientific_visualizations.py # Publication figures
│   ├── visualize_benchmarks.py     # Benchmark visualization
│   ├── compare_results.py           # Compare run results
│   ├── compare_with_tedesco.py     # Compare with Tedesco (2025)
│   ├── compare_nodes.py            # Cross-node comparison
│   └── platform_analyzer.py        # Hardware analysis
│
├── docs/                            # Documentation
│   ├── README.md                    # Quick start
│   ├── CHANGELOG.md                 # Version history (includes v2.0)
│   ├── STATISTICAL_FEATURES.md      # Statistical methodology
│   ├── OUTLIER_HANDLING.md         # Outlier documentation
│   ├── ENHANCEMENTS_INDEX.md       # v2.0 feature index
│   ├── regression_testing.md       # Regression testing guide
│   ├── detect_flaky.md             # Flaky detection guide
│   ├── benchmark_diffing.md        # Baseline comparison guide
│   ├── trend_analysis.md           # Trend tracking guide
│   ├── BENCHMARK_FAIRNESS.md       # Fairness methodology
│   ├── DATA_PROVENANCE.md          # Dataset sources
│   ├── METHODOLOGY_CHEN_REVELS.md   # Chen & Revels methodology
│   ├── METHODOLOGY_NOTES_FOR_THESIS.md # Thesis-specific notes
│   ├── IMPROVEMENTS_SUMMARY.md     # Improvements documentation
│   ├── IMPROVEMENTS.md            # Improvements
│   ├── START_HERE.md              # Getting started
│   ├── START_HERE_v4.md           # v4 getting started
│   ├── QUICK_START.md             # Quick start
│   ├── QUICK_START_MISE.md       # Mise quick start
│   ├── NATIVE_QUICK_START.md     # Native quick start
│   ├── NATIVE_BARE_METAL_GUIDE.md # Bare metal guide
│   ├── CROSS_PLATFORM_NATIVE_GUIDE.md # Cross-platform
│   ├── MISE_CUPRITE_GUIDE.md     # Mise + Cuprite
│   ├── CUPRITE_VS_JASPER_RIDGE.md # Dataset comparison
│   ├── CONTAINER_OPTIMIZATION.md  # Container optimization
│   ├── CONTAINER_OPTIMIZATION_QUICK.md # Quick optimization
│   ├── CONTAINER_OPTIMIZATION_GUIDE.md # Detailed guide
│   ├── GITHUB_CODESPACES.md      # GitHub Codespaces
│   ├── GITHUB_CODESPACES_GUIDE.md # Detailed Codespaces
│   ├── CACHING_GUIDE.md          # Caching documentation
│   ├── SELECTIVE_CACHE_CONTROL.md # Selective caching
│   ├── IMPLEMENTATION_CHECKLIST.md # Implementation checklist
│   ├── TROUBLESHOOTING.md        # Troubleshooting
│   ├── PROGRESS_ASSESSMENT.md    # Progress tracking
│   ├── VERSION_4_CHANGES.md     # v4 changes
│   ├── WHATS_NEW_v4.md          # What's new
│   ├── UPGRADE_TO_V4.md         # Upgrade guide
│   ├── README_v4.md             # v4 README
│   ├── README_COMPLETE_v4.md    # Complete v4 guide
│   ├── README_ENHANCEMENTS.md   # Enhancements README
│   ├── README_OLD.md            # Legacy README
│   └── CHANGELOG_v4.0.md       # v4 changelog
│
├── containers/                      # Container definitions
│   ├── python.Containerfile      # Python container (Fedora 43)
│   ├── julia.Containerfile       # Julia container
│   ├── r.Containerfile           # R container
│   ├── python-optimized.Containerfile  # Optimized Python
│   ├── julia-optimized.Containerfile  # Optimized Julia
│   ├── r-optimized.Containerfile     # Optimized R
│   ├── versions.json             # Semantic versioning
│   └── copies_for_ai/            # AI reference copies
│       ├── python.txt
│       ├── julia.txt
│       └── r.txt
│
├── validation/                     # Cross-language validation
│   ├── thesis_validation.py      # Main validation script
│   └── (expected results)
│
├── results/                        # Benchmark outputs
│   ├── *.json                     # Raw results per benchmark
│   ├── cold_start/                # Cold start benchmarks
│   ├── warm_start/                # Warm start benchmarks
│   ├── scaling/                   # Scaling analysis results
│   ├── figures/                   # Generated plots
│   ├── academic/                  # Formatted tables
│   ├── memory/                    # Memory profiling
│   ├── native/                    # Native benchmarks
│   ├── hardware_info.json         # System information
│   ├── container_hashes.txt      # Container digests
│   ├── thesis_validation_report.md # Validation report
│   ├── benchmark_report.html      # HTML report
│   ├── benchmark_results.tex      # LaTeX report
│   ├── chen_revels_validation_summary.md # CR validation
│   └── errors.log                 # Error log
│
├── data/                           # Benchmark datasets
│   └── (Cuprite, synthetic data)
│
├── .devcontainer/                 # VS Code devcontainer
│   ├── devcontainer.json
│   ├── setup.sh
│   └── codespaces_setup.sh
│
├── benchmark_scaling.py            # Data scaling benchmarks
├── visualize_scaling.py           # Scaling visualization
├── compare_native_vs_container.py  # Compare execution modes
├── run_benchmarks.sh             # Container orchestrator
├── build_optimized.sh            # Build optimized containers
├── build_slim_containers.sh      # Build slim containers
├── native_benchmark.sh           # Native benchmark runner
├── native_helper.sh              # Native helper utilities
├── check_system.sh               # System check
├── cleanup_containers.sh          # Cleanup containers
├── cleanup_podman.sh             # Cleanup podman
├── fix_julia_cache.sh            # Fix Julia cache
├── purge_cache_and_rebuild.sh    # Purge and rebuild
├── pull_containers.sh            # Pull container images
├── AGENTS.md                     # This file
├── README.md                     # Project README
├── Manifest.toml                 # Julia package manifest
└── Project.toml                  # Julia project file
```

---

## Version Management

### mise Configuration
```toml
# .mise.toml
min_version = "2024.1.0"

[tools]
python = "3.13.12"    # Must match container
julia = "1.11.4"      # Must match container
r = "4.5.3"           # Must match container
```

### Container Versions
| Language | Version | Container Tag |
|----------|---------|---------------|
| Python | 3.13.12 | `thesis-python:latest` |
| Julia | 1.11.9 | `thesis-julia:latest` |
| R | 4.5.3 | `thesis-r:latest` |

---

## Task Reference

### mise Tasks
```bash
mise run bench          # Run all benchmarks (native)
mise run bench-python   # Python only
mise run bench-julia   # Julia only
mise run bench-r       # R only
mise run scaling       # Quick scaling (3 runs, small scales)
mise run scaling-full  # Full scaling analysis (10 runs)
mise run viz-scaling   # Visualize scaling results
mise run validate      # Run cross-language validation
mise run viz           # Generate visualizations
mise run report        # Generate report
mise run clean         # Clean results
mise run info          # Show environment info
mise run check         # Verify environment setup
mise run versions      # List installed versions
```

### Direct Execution
```bash
# Container execution (recommended for thesis)
./run_benchmarks.sh

# Scaling benchmarks
python benchmark_scaling.py --quick --runs 3    # Quick test (~1 min)
python benchmark_scaling.py --runs 10           # Full analysis (~30 min)

# Quality assurance
python benchmarks/detect_flaky.py results/ --output=flaky_report.json
python benchmarks/regression_tests.py results/
python benchmarks/test_enhancements.py  # 38 tests

# Visualization
python visualize_scaling.py

# Validation
python validation/thesis_validation.py --all
```

---

## Dataset Provenance

### Cuprite Hyperspectral Dataset
- **Source**: NASA AVIRIS (Airborne Visible/Infrared Imaging Spectrometer)
- **Location**: Cuprite mining district, Nevada
- **Citation**: Boardman et al., 1995
- **License**: Public domain
- **Purpose**: Standard benchmark for hyperspectral analysis

### MODIS NDVI Time-Series
- **Source**: NASA LP DAAC (Level-1 and Atmosphere Archive)
- **Product**: MOD13Q1 (Vegetation Indices)
- **Purpose**: Real satellite data for time-series benchmarking

### Synthetic Data
- Generated via `tools/generate_benchmark_data.py`
- Reproducible with `REPRODUCIBILITY_SEED=42`

---

## Reproducibility

### Seed Configuration
```toml
# .mise.toml
[env]
REPRODUCIBILITY_SEED = "42"
```

### Hardware Configuration
```bash
# Thread pinning
JULIA_NUM_THREADS=8
OPENBLAS_NUM_THREADS=8
OMP_NUM_THREADS=8
```

### Container Isolation
- Each language runs in dedicated container
- Same base OS (Fedora 43)
- Same library versions
- Reproducible builds via Containerfiles

---

## Thesis Integration

### Chapter 4 (Results)
1. Present summary statistics tables
2. Show comparison bar charts with error bars
3. Report statistical significance (p-values)
4. Include effect sizes (Cohen's d)

### Chapter 5 (Discussion)
1. Explain scaling behavior
2. Compare algorithmic complexity
3. Discuss cold vs warm start tradeoffs

### Statistical Reporting Format
```json
{
  "benchmark": "matrix_ops",
  "language": "python",
  "min_time": 0.456,
  "mean": 0.478,
  "std": 0.023,
  "cv": 0.048,
  "median": 0.472,
  "times": [0.456, 0.467, ...],
  "normality": {"test": "shapiro-wilk", "p": 0.234, "normal": true},
  "effect_size": {"cohen_d": 2.34, "interpretation": "large"}
}
```

---

## References

1. Chen, J.Y., & Revels, J. (2016). "Robust Benchmarking in Noisy Environments." arXiv:1608.04295

2. Tedesco, L. et al. (2025). "Multi-scale performance benchmarking of geospatial processing frameworks." To appear.

3. Boardman, J.W. et al. (1995). "Geometric AVIRIS: Radiometric and atmospheric correction of AVIRIS data." Proc. AVIRIS Workshop.

4. Bonferroni, C.E. (1936). "Teoria statistica delle classi e calcolo delle probabilità." Pubblicazioni del Istituto di Statistica.

5. Benjamini, Y., & Hochberg, Y. (1995). "Controlling the false discovery rate." Journal of the Royal Statistical Society.

---

## Maintenance

### Updating Versions
1. Update `.mise.toml` tools section
2. Update container Dockerfiles
3. Update `containers/versions.json`
4. Run full benchmark suite
5. Document in CHANGELOG.md

### Adding New Benchmarks
1. Create `benchmarks/new_benchmark.{py,jl,R}`
2. Implement same interface as existing benchmarks
3. Add `common_hash.jl` and `common_hash.R` for cross-language validation
4. Add to `run_benchmarks.sh`
5. Add to `.mise.toml` bench tasks
6. Add tests to `test_enhancements.py`
7. Update documentation

---

**Document Version**: 2.0  
**Last Updated**: April 2026  
**Framework Version**: v2.0 (Statistical Enhancements)
