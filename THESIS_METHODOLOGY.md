# Chapter 3: Research Methodology

## 3.1 Experimental Design Overview

This research employs a rigorous computational benchmarking framework to evaluate the performance of Julia (v1.12.6) against the industry-standard scientific languages Python (v3.14) and R (v4.5.x) within the context of Geographic Information Systems (GIS) and Remote Sensing (RS) workflows. The methodology is designed to prioritize three core pillars:

### 3.1.1 Scientific Rigor

We follow the **Chen & Revels (2016)** methodology for robust benchmarking, which recognizes that timing measurements in modern operating systems are **non-independent and identically distributed (non-i.i.d.)** due to background interrupts, context switching, cache effects, garbage collection pauses, and thermal throttling. This invalidates classical statistical approaches (t-tests, ANOVA) that assume normality and independence.

**Our protocol**:
1. **Warmup phase**: 5 initial runs to stabilize Just-In-Time (JIT) compilation (Julia) and system caches
2. **Sample size**: 30 independent repetitions per benchmark (Central Limit Theorem threshold for stable bootstrap confidence intervals)
3. **Primary estimator**: **Minimum execution time** — the run with the fewest aggregate delay factors
4. **Confidence intervals**: 95% Bootstrap CIs (non-parametric, no i.i.d. assumption)

### 3.1.2 Computational Fairness

All three language ecosystems are configured to use identical computational resources:
- **Same BLAS backend**: OpenBLAS via FlexiBLAS abstraction layer
- **Same thread count**: 8 threads across all ecosystems
- **Same CPU affinity**: Locked to physical cores 0-7 via `numactl`
- **Same random seeds**: Seed=42 for all synthetic data generation
- **Same input data**: Real datasets (AVIRIS Cuprite, Natural Earth) shared across languages

### 3.1.3 Bare-Metal Reproducibility

We eliminate the "virtualization tax" of Docker containers and virtual machines by using a custom **bootc (Bootable Container)** operating system that boots directly on bare metal:
- **Immutable OS**: Filesystem cannot drift; exact package versions guaranteed
- **Atomic updates**: Roll back to any previous image if something breaks
- **Content-addressable**: Every deployment verified by cryptographic hash (SHA-256)
- **Zero hypervisor overhead**: Direct hardware access, no virtualization layer

---

## 3.2 Infrastructure: The bootc Bare-Metal Appliance

### 3.2.1 System Specifications

| Component | Specification | Purpose |
|-----------|--------------|---------|
| **Operating System** | Fedora Silverblue (bootc) v43 | Immutable, reproducible base |
| **Kernel** | Linux 6.x | System kernel with performance optimizations |
| **Hardware** | Intel Core i5-8350U (4 cores, 8 threads) | Reference platform |
| **Memory** | 16 GB RAM | Sufficient for large datasets |
| **Storage** | NVMe SSD | High-throughput I/O |

### 3.2.2 OS Optimization

1. **CPU Frequency Scaling**: Locked to `performance` governor (disables dynamic frequency scaling that causes timing variance)
2. **Filesystem Cache Clearing**: `sync; echo 3 > /proc/sys/vm/drop_caches` between language transitions
3. **CPU Affinity**: `numactl --physcpubind=0-7` pins benchmarks to specific cores
4. **NUMA Binding**: `numactl --cpunodebind=0 --membind=0` ensures consistent memory access latency
5. **Background Services**: Minimized to reduce OS noise (no desktop environment in benchmark mode)

### 3.2.3 The Decoupled Architecture

The system is split into two repositories:

| Layer | Repository | Responsibility | Update Frequency |
|-------|-----------|----------------|------------------|
| **Appliance** | `benchmark-bootc` | OS, runtimes, C++ libraries, system tuning | Rarely (when dependencies change) |
| **Logic** | `benchmark-thesis` | Benchmark code, orchestration, analysis, datasets | Frequently (daily research workflow) |

This decoupling ensures that fixing a benchmark bug or adding a new test does not require rebuilding the 8GB OS image.

---

## 3.3 Software Stack and Library Parity

### 3.3.1 Language Runtimes

| Language | Version | Runtime Engine | Key Characteristics |
|----------|---------|---------------|---------------------|
| **Julia** | 1.12.6 | LLVM JIT compiler | Multiple dispatch, native parallelism |
| **Python** | 3.14.x | CPython (interpreted) | Global Interpreter Lock (GIL), C extensions |
| **R** | 4.5.x | GNU R (interpreted) | Vectorized operations, statistical focus |

### 3.3.2 Geospatial Libraries

| Language | Library | Purpose | Backend |
|----------|---------|---------|---------|
| **Julia** | ArchGDAL.jl | Raster/vector I/O | GDAL (C++) |
| **Julia** | GeoDataFrames.jl | Tabular geospatial data | GDAL, GEOS |
| **Julia** | LibGEOS.jl | Computational geometry | GEOS (C++) |
| **Python** | GeoPandas | Vector data | Fiona, Shapely, GEOS |
| **Python** | Rasterio | Raster data | GDAL (C++) |
| **Python** | pyproj | Coordinate transforms | PROJ (C) |
| **R** | sf | Simple Features (vector) | GDAL, PROJ, GEOS |
| **R** | terra | Raster and vector | GDAL, PROJ |

**Key observation**: All three ecosystems ultimately call the **same underlying C/C++ libraries** (GDAL, PROJ, GEOS) for geospatial operations. This ensures that performance differences reflect the **language-level overhead** (parsing, dispatch, memory management) rather than differences in the underlying algorithms.

### 3.3.3 Linear Algebra Standardization

**What is BLAS?** BLAS (Basic Linear Algebra Subprograms) is a standardized specification for low-level linear algebra routines (vector addition, dot products, matrix multiplication, etc.). It is the computational foundation of all numerical computing.

**What is LAPACK?** LAPACK (Linear Algebra Package) builds on BLAS to provide higher-level operations (LU/QR/SVD decomposition, eigenvalue computation, etc.).

**Why does this matter?** Python's NumPy, Julia's LinearAlgebra, and R's base math all delegate to a BLAS implementation. If different languages use different BLAS libraries (e.g., OpenBLAS vs Intel MKL vs BLIS), the comparison becomes unfair — you're measuring BLAS performance, not language performance.

**Our solution**: All languages use **OpenBLAS** via the **FlexiBLAS** abstraction layer:

```bash
# Force all languages to use OpenBLAS
flexiblas default OPENBLAS
export FLEXIBLAS=OPENBLAS-OPENMP
```

This ensures that `numpy.dot(A, B)`, `A * B` in Julia, and `crossprod(A, B)` in R all execute the **same OpenBLAS kernel code**.

### 3.3.4 Thread Configuration

| Variable | Value | Purpose |
|----------|-------|---------|
| `JULIA_NUM_THREADS` | 8 | Julia's parallel threading |
| `OPENBLAS_NUM_THREADS` | 8 | OpenBLAS thread pool |
| `FLEXIBLAS_NUM_THREADS` | 8 | FlexiBLAS thread pool |
| `GOTO_NUM_THREADS` | 8 | GotoBLAS thread pool (fallback) |
| `OMP_NUM_THREADS` | 8 | OpenMP thread pool |

**Why 8?** The Intel Core i5-8350U has 4 physical cores with Hyper-Threading (8 logical cores). Using 8 threads maximizes parallelism without oversubscribing the CPU.

---

## 3.4 Statistical Protocol (Chen & Revels, 2016)

### 3.4.1 The Problem with Mean and Median

Traditional benchmarking uses the **mean** (average) or **median** (middle value) as the primary performance metric. However, Chen & Revels (2016) demonstrated that this approach is fundamentally flawed because:

1. **Timing measurements are not i.i.d.**: Each measurement is affected by the system state at the time of execution (CPU frequency, cache contents, background processes).
2. **Delay factors are non-negative**: Background processes can only slow down execution, never speed it up.
3. **The minimum is the most stable estimator**: It has the lowest coefficient of variation across repeated trials.

### 3.4.2 The Mathematical Model

```
T_measured = T_true + Σ(delay_i)

where:
  T_measured = observed execution time
  T_true = true algorithmic execution time
  delay_i = individual delay factors (≥ 0)
```

**Key insight**: Since all `delay_i ≥ 0` (delays never speed up execution), the **minimum** observed time has the smallest aggregate delay contribution:

```
min(T_1, T_2, ..., T_n) = T_true + min(Σ delay_1, Σ delay_2, ..., Σ delay_n)
```

Therefore, the minimum is the closest approximation to `T_true` — the true algorithmic performance.

### 3.4.3 Our Implementation

```python
# Protocol:
for _ in range(5):     # Warmup (not measured)
    run_benchmark()

times = []
for _ in range(30):    # Benchmark (measured)
    t_start = time.perf_counter_ns()
    run_benchmark()
    t_end = time.perf_counter_ns()
    times.append((t_end - t_start) / 1e9)

# Primary metric
min_time = min(times)

# Context metrics (reported but not used for comparison)
mean_time = sum(times) / len(times)
median_time = sorted(times)[len(times) // 2]
```

### 3.4.4 Confidence Intervals

We use **bootstrap resampling** (1,000 resamples) to compute 95% confidence intervals for the minimum:

```python
import numpy as np

def bootstrap_ci(data, n_bootstrap=1000, alpha=0.05):
    """Compute bootstrap confidence interval for minimum."""
    bootstrap_mins = []
    for _ in range(n_bootstrap):
        sample = np.random.choice(data, size=len(data), replace=True)
        bootstrap_mins.append(np.min(sample))
    lower = np.percentile(bootstrap_mins, alpha * 100 / 2)
    upper = np.percentile(bootstrap_mins, (1 - alpha / 2) * 100)
    return lower, upper
```

**Interpretation**: If the 95% CIs for two languages do not overlap, the difference is statistically significant at p < 0.05.

---

## 3.5 Benchmark Scenarios

### 3.5.1 Scenario Selection Criteria

Benchmarks were selected to cover the full spectrum of GIS/RS computational patterns:

| Category | Benchmarks | Computational Pattern |
|----------|-----------|----------------------|
| **Numerical** | Matrix Ops | Dense linear algebra (O(n³)) |
| **I/O** | I/O Operations | Sequential file access (O(n)) |
| **Remote Sensing** | Hyperspectral SAM, NDVI Time-Series, Raster Algebra | Vectorized array operations |
| **Spatial Analysis** | Vector PiP, IDW Interpolation, Zonal Stats | Geometry computations, spatial joins |
| **Geodesy** | Coordinate Reprojection | Coordinate transformations |

### 3.5.2 Detailed Scenarios

| # | Scenario | Data | Languages | Complexity | Primary Operation |
|---|----------|------|-----------|------------|-------------------|
| 1 | Matrix Operations | 2500×2500 synthetic | Python, Julia, R | O(n³) | BLAS matrix multiplication |
| 2 | I/O Operations | 1M rows CSV/binary | Python, Julia, R | O(n) | File read/write |
| 3 | Hyperspectral SAM | 224×512×614 Cuprite | Python, Julia, R | O(n×m×b) | Cosine similarity |
| 4 | Vector PiP | 4,274 polygons, 520K points | Python, Julia, R | O(n log m) | Spatial join |
| 5 | IDW Interpolation | 50K points, 1M grid | Python, Julia, R | O(n×m×log m) | K-NN search |
| 6 | NDVI Time-Series | 12×500×500 synthetic | Python, Julia, R | O(n×m×t) | Temporal reduction |
| 7 | Raster Algebra | 4 bands × 512×614 | Python, Julia, R | O(n×m) | Element-wise math |
| 8 | Zonal Statistics | 10 zones, 600×600 raster | Python, Julia, R | O(n×m×p) | Raster-vector overlay |
| 9 | Reprojection | 1K-10K points | Python, Julia, R | O(n) | Coordinate transform |

---

## 3.6 Dual-Data Strategy

### 3.6.1 Real-World Datasets (Domain Relevance)

We use real geospatial datasets to ensure benchmarks reflect actual usage:

| Dataset | Source | Format | Size | Used In |
|---------|--------|--------|------|---------|
| AVIRIS Cuprite | USGS | .mat (MATLAB) | ~90 MB | Hyperspectral SAM, Raster Algebra |
| Natural Earth Admin-0 | Natural Earth | .shp | ~10 MB | Vector PiP, Zonal Stats |
| NLCD Land Cover | USGS | .bin | ~1.4 MB | Zonal Stats |

### 3.6.2 Synthetic Datasets (Complexity Validation)

Following Tedesco et al. (2025), we generate synthetic datasets on-the-fly with identical random seeds (42) across all languages to:
1. **Validate algorithmic complexity**: Confirm O(n), O(n²), O(n³) scaling
2. **Identify performance cliffs**: Detect where data size exceeds CPU cache levels
3. **Ensure identical inputs**: Same data for all languages, eliminating data-dependent variance

**Synthetic datasets**:
- Matrix data: 2500×2500 Float64, seed=42
- I/O data: 1M rows × 5 columns, seed=42
- Interpolation points: 50,000 scattered (x,y,z), seed=42
- NDVI time series: 12×500×500 5-band stack, seed=42
- Reprojection points: 1K-10K random lat/lon, seed=42

---

## 3.7 Reproducibility

### 3.7.1 Environment Reproducibility

The bootc OS ensures that every deployment uses the **exact same** software stack:
- **Image hash**: SHA-256 digest verifies image integrity
- **Locked versions**: All packages pinned to specific versions
- **Immutable filesystem**: No runtime drift

### 3.7.2 Result Reproducibility

- **Random seeds**: All synthetic data uses seed=42
- **Deterministic algorithms**: Same inputs → same outputs
- **Validation hashes**: SHA-256 of results confirms numerical equivalence
- **Open data**: All datasets are publicly available

### 3.7.3 Code Reproducibility

- **Open source**: All code under MIT License
- **Version controlled**: Git history tracks all changes
- **CI/CD**: Automated testing on every commit
- **Container fallback**: Can run in Docker/Podman if bootc unavailable

---

## 3.8 Limitations

1. **Single hardware platform**: Results may vary on different CPUs (though bootc supports multi-arch fat binaries)
2. **Library-level vs language-level**: Some benchmarks measure library performance (GeoPandas vs sf) rather than pure language performance
3. **JIT overhead**: Julia's first-run compilation time is not captured in warm-start benchmarks (addressed separately via `jit_tracking.py`)
4. **Real-world datasets**: Cuprite data is from 1995; newer sensors may have different characteristics

---

*This methodology ensures that the results presented in this thesis are reproducible, fair, and statistically significant, satisfying the requirements for scientific publication in the field of Geoinformatics.*
