# Chapter 3: Research Methodology

## 3.1 Experimental Design Overview
This research employs a rigorous computational benchmarking framework to evaluate the performance of Julia (v1.12.6) against the industry-standard scientific languages Python (v3.14) and R (v4.5.x) within the context of Geographic Information Systems (GIS) and Remote Sensing (RS) workflows. The methodology is designed to prioritize three core pillars: **Scientific Rigor**, **Computational Fairness**, and **Bare-Metal Reproducibility**.

## 3.2 Infrastructure: The bootc Bare-Metal Appliance
To eliminate the performance variance (the "virtualization tax") introduced by standard Docker/Podman containers or Virtual Machines, this study utilizes a custom-built, immutable operating system based on the **Fedora bootc (Bootable Container)** standard.

### 3.2.1 System Specifications
- **Operating System**: Fedora Silverblue (bootc) v43.
- **Kernel**: Linux 6.x (Optimized for performance).
- **Isolation**: Bare-metal execution (Zero hypervisor overhead).
- **Optimization**: CPU frequency scaling was locked to `performance` mode, and filesystem caches were dropped (`sync; echo 3 > /proc/sys/vm/drop_caches`) between every language transition to ensure a "clean-room" environment.

## 3.3 Software Stack and Library Parity
A fundamental requirement for language comparison is the use of comparable high-performance libraries. We have standardized the stack as follows:

| Language | Engine | Geospatial Libraries | Linear Algebra |
| :--- | :--- | :--- | :--- |
| **Julia** | v1.12.6 (LLVM) | ArchGDAL.jl, GeoDataFrames.jl | OpenBLAS |
| **Python** | v3.14 (CPython) | GeoPandas, Rasterio, NumPy | OpenBLAS |
| **R** | v4.5.x | sf, terra, data.table | OpenBLAS |

### 3.3.1 Linear Algebra Standardization
All languages were linked to **OpenBLAS (v0.3.28)** and restricted to **8 computational threads** (`JULIA_NUM_THREADS=8`, `OPENBLAS_NUM_THREADS=8`). This ensures that differences in execution time are attributable to the language runtime and compiler efficiency rather than variations in low-level BLAS/LAPACK implementations.

## 3.4 Statistical Protocol (Chen & Revels, 2016)
Timing measurements in modern operating systems are non-independent and identically distributed (non-i.i.d.) due to background interrupts and context switching. Following the methodology proposed by **Chen & Revels (2016)**, we adopt the following protocol:

1.  **Warmup Phase**: Each benchmark is executed for 5 warmup runs to allow for Julia's Just-In-Time (JIT) compilation and system cache stabilization.
2.  **Sample Size**: 30 independent repetitions are recorded for every scenario.
3.  **Primary Estimator**: The **Minimum Execution Time** is used as the primary performance metric. Mathematically, the minimum represents the run with the fewest aggregate delay factors, providing the most accurate estimate of the language's theoretical peak performance.
4.  **Confidence Intervals**: 95% Bootstrap Confidence Intervals are calculated to assess the stability and significance of the results.

## 3.5 Dual-Data Strategy
To provide both industry relevance and algorithmic validation, we utilize a two-tiered data approach:

### 3.5.1 Real-World Datasets (Domain Relevance)
- **Hyperspectral**: NASA AVIRIS Cuprite dataset (224 bands, MAT format). Used for Spectral Angle Mapper (SAM) benchmarks.
- **Vector**: Natural Earth Admin-0 Countries (Global scale). Used for Point-in-Polygon and Zonal Statistics benchmarks.

### 3.5.2 Synthetic Scaling (Complexity Validation)
Following **Tedesco et al. (2025)**, we perform multi-scale benchmarking (k=1 to k=4). Synthetic datasets are generated on-the-fly using identical random seeds (42) across all languages to validate algorithmic complexity ($O(n)$, $O(n \log n)$, $O(n^3)$) and identify performance "cliffs" as data volume exceeds CPU cache levels.

## 3.6 Evaluation Scenarios
The benchmarking suite evaluates the following representative GIS/RS tasks:
1.  **Matrix Operations**: LU Decomposition and Cross-Products (Computational baseline).
2.  **I/O Performance**: High-speed CSV and Binary read/write.
3.  **Hyperspectral Analysis**: Vectorized SAM pixel classification.
4.  **Raster-Vector Overlay**: Zonal statistics using irregular polygons.
5.  **Time-Series Analysis**: OLS trend estimation on NDVI stacks.
6.  **Spatial Interpolation**: Inverse Distance Weighting (IDW).

---
*This methodology ensures that the results presented in this thesis are reproducible, fair, and statistically significant, satisfying the requirements for scientific publication in the field of Geoinformatics.*
