# =============================================================================
# ULTRA-OPTIMIZED THESIS JULIA CONTAINER
# Size: ~400MB (with packages)
# Build time: ~5-10 min
# =============================================================================

FROM julia:1.11-bookworm

ENV JULIA_VERSION=1.11.9

RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenblas-dev \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libsqlite3-dev \
    gdal-bin \
    proj-bin \
    hyperfine \
    time \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

ENV JULIA_NUM_THREADS=8 \
    OPENBLAS_NUM_THREADS=8 \
    OMP_NUM_THREADS=8

WORKDIR /benchmarks
CMD ["/bin/bash"]
