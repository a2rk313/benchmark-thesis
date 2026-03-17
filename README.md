# Computational Benchmarking: Julia vs Python vs R for GIS/RS Workflows

**Cross-Platform Native Benchmarking with mise**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.12](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/downloads/)
[![Julia 1.11](https://img.shields.io/badge/julia-1.11-purple.svg)](https://julialang.org/)
[![R 4.4](https://img.shields.io/badge/R-4.4-blue.svg)](https://www.r-project.org/)

## 🚀 Quick Start (5 Minutes)

### On Fedora Atomic (Aurora) / Linux

```bash
# Install mise
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# Clone and setup
cd thesis-benchmarks

# Install languages and packages
mise install
mise run install

# Download datasets
mise run download-data

# Run benchmarks
mise run bench
```

### On Windows

```powershell
# Install mise
winget install jdx.mise

# Clone and setup
cd thesis-benchmarks

# Install languages and packages
mise install
mise run install

# Download datasets
mise run download-data

# Run benchmarks
mise run bench
```

**That's it!** Same commands work on both platforms.

---

## 📚 What's New

### ⭐ Version 4.0 - mise + Cuprite Update

**Major Improvements**:

1. **mise Integration** - Cross-platform version manager
   - Single `.mise.toml` config for all platforms
   - No containers needed (native performance)
   - No 6-month Windows package lag
   - 5-minute setup

2. **Cuprite Dataset** - Replaced Jasper Ridge
   - Industry standard (1000+ citations)
   - Freely available (NASA public domain)
   - Better reproducibility
   - Equivalent computational characteristics

3. **Scaling Analysis** - Multi-scale benchmarking
   - 4 data scales per benchmark
   - Complexity validation (O(n²), O(n³), etc.)
   - Comparison with Tedesco et al. (2025)

4. **Native Benchmarking** - Container overhead analysis
   - Bare-metal performance testing
   - Container vs native comparison
   - CPU optimization scripts

---

## 📊 Benchmarks

| Benchmark | Dataset | Complexity | Languages |
|-----------|---------|------------|-----------|
| **Matrix Operations** | Synthetic | O(n³) | Python, Julia, R |
| **I/O Operations** | Synthetic | O(n) | Python, Julia, R |
| **Hyperspectral** | AVIRIS Cuprite | 224 bands | Python, Julia, R |
| **Vector PiP** | Natural Earth | 255 polygons | Python, Julia, R |
| **IDW Interpolation** | Natural Earth | O(n²) | Python, Julia, R |
| **NDVI Time Series** | Synthetic | Temporal | Python, Julia, R |

**Real Data: 60%** (Natural Earth, AVIRIS Cuprite, Derived IDW)

---

## 🎯 Usage

```bash
# List all tasks
mise tasks

# Setup
mise run install          # Install dependencies
mise run download-data    # Download Cuprite

# Run
mise run bench           # All benchmarks
mise run validate        # Validation
mise run scaling         # Multi-scale

# Analyze
mise run check           # Verify setup
mise run clean           # Clean results
```

---

## 📖 Documentation

**Quick Start**:
- [QUICK_START_MISE.md](QUICK_START_MISE.md) - 5-minute guide
- [MISE_CUPRITE_GUIDE.md](MISE_CUPRITE_GUIDE.md) - Complete guide

**Methodology**:
- [METHODOLOGY_CHEN_REVELS.md](METHODOLOGY_CHEN_REVELS.md) - Why minimum > mean
- [DATA_PROVENANCE.md](DATA_PROVENANCE.md) - Dataset justification

**Advanced**:
- [NATIVE_BARE_METAL_GUIDE.md](NATIVE_BARE_METAL_GUIDE.md) - Native benchmarking
- [CUPRITE_VS_JASPER_RIDGE.md](CUPRITE_VS_JASPER_RIDGE.md) - Dataset comparison

---

## 🔬 Methodology

Following **Chen & Revels (2016)**:
- Use **minimum time** (not mean/median)
- Mathematical proof: T_measured = T_true + Σ(delays)
- Delays ≥ 0, so minimum approximates truth

Validated against **Tedesco et al. (2025)** spatio-temporal benchmarks.

---

## 🌍 Cross-Platform

Tested on:
- ✅ Fedora Atomic (Aurora)
- ✅ Ubuntu 22.04 / 24.04
- ✅ Windows 11
- ✅ macOS (Ventura+)

Lock files:
- Python: `requirements.txt`
- Julia: `Manifest.toml`
- R: `renv.lock`

---

## 📚 Citations

**Dataset**:
```
Boardman, J. W., Kruse, F. A., & Green, R. O. (1995). 
Mapping target signatures via partial unmixing of AVIRIS data.
```

**Methodology**:
```
Chen, J., & Revels, J. (2016). Robust benchmarking in noisy environments.
arXiv:1608.04295.

Tedesco, L., et al. (2025). Computational benchmark study in spatio-temporal statistics.
Environmetrics. doi:10.1002/env.70017
```

---

## 🎓 Thesis Support

This code supports: **"Computational Benchmarking of Julia vs Python vs R for GIS/RS Workflows"**

**Key Findings** (Expected):
- Julia: Best for matrix ops, compile-once workflows
- Python: Best ecosystem, library availability
- R: Best for stats, I/O with data.table
- Platform variance: <5% for compute tasks

---

**Version**: 4.0.0 - mise + Cuprite Update  
**Last Updated**: March 15, 2026
