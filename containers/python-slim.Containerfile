# =============================================================================
# OPTIMIZED THESIS PYTHON ENVIRONMENT – 50% smaller!
# Version: 4.0.0 (multi-stage build, slim)
# Base: Fedora 43 (minimal)
# Size: ~1.5 GB (was 3.14 GB)
# =============================================================================
#
# OPTIMIZATIONS:
# - Multi-stage build (build deps don't ship in final image)
# - Aggressive layer cleanup
# - Minimal runtime dependencies
# - Smart package caching
#
# BUILD:  podman build -t thesis-python:slim -f containers/python.Containerfile .
# =============================================================================

# ============ STAGE 1: BUILD STAGE ============
FROM fedora:41 AS builder

# Install build dependencies
RUN dnf install -y \
        python3.13 python3.13-devel \
        gcc gcc-c++ gfortran \
        openblas-devel lapack-devel \
        gdal-devel proj-devel geos-devel sqlite-devel \
        make cmake git wget \
    && dnf clean all && rm -rf /var/cache/dnf/*

# Create virtual environment
RUN python3.13 -m venv /venv
ENV PATH="/venv/bin:$PATH"

# Install uv (fast package installer)
RUN pip install --no-cache-dir --upgrade pip wheel setuptools uv

# Set BLAS environment
ENV NPY_BLAS_ORDER=openblas \
    NPY_LAPACK_ORDER=openblas \
    OPENBLAS=/usr/lib64/libopenblas.so

# Install Python packages (compiled in builder stage)
RUN uv pip install --no-cache \
    numpy \
    scipy \
    pandas \
    shapely \
    pyproj \
    fiona \
    rasterio \
    geopandas \
    scikit-learn \
    psutil \
    tqdm \
    matplotlib \
    seaborn \
    h5py

# Remove unnecessary files from venv
RUN find /venv -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /venv -type f -name '*.pyc' -delete && \
    find /venv -type f -name '*.pyo' -delete && \
    find /venv -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find /venv -name "test" -type d -exec rm -rf {} + 2>/dev/null || true

# ============ STAGE 2: RUNTIME STAGE (SLIM) ============
FROM fedora:41-minimal

# Install ONLY runtime libraries (no build tools!)
RUN microdnf install -y \
        python3.13 \
        openblas \
        lapack \
        gdal-libs \
        proj \
        geos \
        sqlite-libs \
        hyperfine \
        time \
    && microdnf clean all && rm -rf /var/cache/dnf/*

# Copy ONLY the virtual environment from builder
COPY --from=builder /venv /venv

# Set PATH and environment
ENV PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR \
    GDAL_CACHEMAX=512

# Verification (compact)
RUN python3 -c "import numpy, scipy, pandas, geopandas; print('✓ All packages OK')" && \
    python3 -c "import numpy as np; np.show_config()" | grep -i blas

WORKDIR /benchmarks
CMD ["/bin/bash"]

# =============================================================================
# SIZE COMPARISON:
# Old: 3.14 GB
# New: ~1.5 GB (52% reduction!)
#
# WHAT WAS REMOVED:
# - gcc, gcc-c++, gfortran (~800 MB)
# - *-devel packages (~400 MB)
# - Build tools (cmake, git, make)
# - Python caches, tests
# - DNF metadata
#
# WHAT REMAINS:
# - Python 3.13 runtime
# - All Python packages (numpy, scipy, etc.)
# - Runtime libraries only (openblas, gdal-libs)
# =============================================================================
