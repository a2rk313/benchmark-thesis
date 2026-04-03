# =============================================================================
# OPTIMIZED THESIS PYTHON ENVIRONMENT – 50-60% smaller
# Version: 4.0.0 (optimized multi-stage build)
# Base: Fedora 43
# Expected size: ~1.2-1.5 GB (was 3.14 GB)
# =============================================================================
#
# OPTIMIZATION TECHNIQUES:
# - Multi-stage build (build deps removed from final image)
# - Aggressive cache cleaning
# - Minimal runtime dependencies
# - Layer consolidation
#
# BUILD:  podman build -t thesis-python:3.13-slim -f containers/python-optimized.Containerfile .
# =============================================================================

# ============================================
# STAGE 1: Build stage (all build dependencies)
# ============================================
FROM fedora:41 AS builder

# Install build dependencies
RUN dnf install -y \
        python3.13 python3.13-devel \
        gcc gcc-c++ gfortran \
        openblas-devel lapack-devel \
        gdal-devel proj-devel geos-devel sqlite-devel \
        make cmake git wget \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Create virtual environment
RUN python3.13 -m venv /venv
ENV PATH="/venv/bin:$PATH"

# Install uv and build tools
RUN pip install --no-cache-dir --upgrade pip wheel setuptools && \
    pip install --no-cache-dir uv

# Set BLAS environment
ENV NPY_BLAS_ORDER=openblas \
    NPY_LAPACK_ORDER=openblas \
    OPENBLAS=/usr/lib64/libopenblas.so

# Install Python packages (compiled here, copied to final stage)
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

# ============================================
# STAGE 2: Runtime stage (minimal dependencies only)
# ============================================
FROM fedora:41

# Install ONLY runtime libraries (no build tools!)
RUN dnf install -y \
        python3.13 \
        openblas lapack \
        gdal-libs proj geos sqlite \
        hyperfine time \
    && dnf clean all \
    && rm -rf /var/cache/dnf/* /tmp/* /var/tmp/*

# Copy virtual environment from builder
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH"

# Verify installation (this will fail the build if packages are missing)
RUN python3 -c "import numpy, scipy, pandas, geopandas; print('✓ Core packages OK')"

# Runtime environment
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR \
    GDAL_CACHEMAX=512

WORKDIR /benchmarks
CMD ["/bin/bash"]

# Final size: ~1.2-1.5 GB (down from 3.14 GB)
