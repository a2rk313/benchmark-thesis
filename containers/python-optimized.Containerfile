# =============================================================================
# ULTRA-OPTIMIZED THESIS PYTHON CONTAINER
# Size: ~500MB (with packages)
# Build time: ~3-5 min
# =============================================================================

FROM python:3.13-slim-bookworm

ENV PYTHON_VERSION=3.13.12

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libspatialindex-dev \
    libblas-dev \
    liblapack-dev \
    libopenblas-dev \
    gdal-bin \
    proj-bin \
    hyperfine \
    time \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

ENV OPENBLAS_NUM_THREADS=8 \
    OMP_NUM_THREADS=8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR \
    GDAL_CACHEMAX=512 \
    NPY_BLAS_ORDER=openblas \
    NPY_LAPACK_ORDER=openblas

WORKDIR /benchmarks
CMD ["/bin/bash"]
