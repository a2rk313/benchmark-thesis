# Computational Benchmarking: Julia vs Python vs R for GIS/RS Workflows

**Cross-Platform Native Benchmarking with mise - Academic Rigor Edition**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.13](https://img.shields.io/badge/python-3.13-blue.svg)](https://www.python.org/downloads/)
[![Julia 1.11](https://img.shields.io/badge/julia-1.11-purple.svg)](https://julialang.org/)
[![R 4.5](https://img.shields.io/badge/R-4.5-blue.svg)](https://www.r-project.org/)

## Quick Start

```bash
# Install mise
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# Clone and setup
cd thesis-benchmarks
mise install

# Install system dependencies (Fedora)
sudo dnf install -y openblas openblas-devel hyperfine

# Run full suite
mise run bench
```

## Key Features

- **Unified Infrastructure**: Single scripts for data, visualization, and validation
- **Academic Rigor**: Statistical tests, confidence intervals, CPU pinning
- **Fair Comparison**: Same BLAS (OpenBLAS, 8 threads) for all languages
- **Containerized**: Docker/Podman for reproducible environments
- **Real Datasets**: AVIRIS Cuprite, Natural Earth, SRTM DEM

## Quick Commands

```bash
mise run bench        # Run all benchmarks
mise run viz          # Generate visualizations
mise run validate     # Cross-language validation
mise run check        # Verify setup
mise run download-data # Download/verify datasets
```

## Benchmark Scenarios

| Scenario | Dataset | Languages |
|----------|---------|----------|
| Matrix Operations | Synthetic 2500×2500 | Python, Julia, R |
| I/O Operations | CSV/Binary | Python, Julia, R |
| Hyperspectral SAM | AVIRIS Cuprite | Python, Julia, R |
| Vector PiP | Natural Earth | Python, Julia, R |
| IDW Interpolation | Synthetic | Python, Julia, R |
| NDVI Time Series | Synthetic | Python, Julia, R |
| Raster Algebra | SRTM DEM | Python, Julia, R |
| Zonal Statistics | NLCD | Python, Julia, R |
| Reprojection | Synthetic | Python, Julia, R |

## Fair Benchmarking Requirements

### BLAS Configuration
All languages use **OpenBLAS** with **8 threads** for matrix operations:

```bash
# Python/Julia (environment variables)
export OPENBLAS_NUM_THREADS=8
export JULIA_NUM_THREADS=8

# R (link to OpenBLAS)
# Already linked in mise installation
```

### R OpenBLAS Setup
R uses reference BLAS by default (65× slower!). Ensure OpenBLAS:

```bash
# Fedora
sudo dnf install openblas

# Ubuntu
sudo apt install libopenblas-dev

# Arch/CachyOS
sudo pacman -S openblas
```

## Directory Structure

```
thesis-benchmarks/
├── benchmarks/           # Benchmark scripts per language
│   ├── matrix_ops.py/jl/R
│   ├── io_ops.py/jl/R
│   └── ...
├── tools/                # Unified infrastructure
│   ├── download_data.py  # All data downloading
│   └── thesis_viz.py     # All visualizations
├── validation/           # Validation suite
│   └── thesis_validation.py
├── results/              # Output directory
│   ├── figures/          # Generated plots
│   └── *.json            # Benchmark results
├── containers/           # Dockerfiles
└── .mise.toml           # Version configuration
```

## Methodology

### Chen & Revels (2016) Estimator Selection
- **Primary metric**: Minimum time (not mean/median)
- **Rationale**: T_measured = T_true + Σ(delays), delays ≥ 0
- **50 runs** per benchmark for statistical power

### Academic Rigor Features
- CPU pinning (taskset) for consistent timings
- Warmup runs (5 + 3 cache iterations)
- Bootstrap confidence intervals (95%, 99%)
- Wilcoxon signed-rank test
- Friedman test for multiple comparisons
- Shapiro-Wilk normality testing

## Results

Benchmark results saved to `results/*.json`:

```bash
# Generate visualizations
python tools/thesis_viz.py --all

# Run validation
python validation/thesis_validation.py --all

# Generate LaTeX tables
python benchmarks/academic_stats.py --latex
```

## Container Support

```bash
# Build containers
./run_benchmarks.sh --build

# Run with containers
./run_benchmarks.sh --container-only

# Native + container comparison
./run_benchmarks.sh --full
```

## Dependencies

### System (Fedora)
```bash
sudo dnf install -y \
    openblas openblas-devel \
    hyperfine \
    time sysstat \
    podman
```

### Python
```bash
pip install -r requirements.txt
```

### Julia
```bash
julia -e 'using Pkg; Pkg.instantiate()'
```

### R
```r
install.packages(c("jsonlite", "sf", "terra"))
```

## Citation

```
Thesis: Computational Benchmarking of Julia vs Python vs R 
        for GIS/Remote Sensing Workflows

Methodology:
  Chen, J., & Revels, J. (2016). Robust benchmarking in noisy 
  environments. arXiv:1608.04295.

  Tedesco, L., et al. (2025). Computational benchmark study 
  in spatio-temporal statistics. Environmetrics.
  doi:10.1002/env.70017

Dataset:
  Boardman, J. W., et al. (1995). Mapping target signatures 
  via partial unmixing of AVIRIS data.
```

## License

MIT License
