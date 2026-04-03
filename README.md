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

## Documentation

See the [docs/](docs/) folder for all guides and documentation.

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

## Citation

```
Thesis: Computational Benchmarking of Julia vs Python vs R 
        for GIS/Remote Sensing Workflows

Methodology:
  Chen, J., & Revels, J. (2016). Robust benchmarking in noisy 
  environments. arXiv:1608.04295.

  Tedesco, L., et al. (2025). Computational benchmark study 
  in spatio-temporal statistics. Environmetrics.
```

## License

MIT License
