# =============================================================================
# ULTRA-OPTIMIZED THESIS R CONTAINER
# Size: ~600MB (with packages)
# Build time: ~5-10 min
# =============================================================================

FROM r-base:4.5.3

ENV R_VERSION=4.5.3

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libsqlite3-dev \
    libudunits2-dev \
    libopenblas-dev \
    gdal-bin \
    proj-bin \
    hyperfine \
    time \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

ENV OMP_NUM_THREADS=8 \
    OPENBLAS_NUM_THREADS=8 \
    R_MAX_VSIZE=16G \
    R_LIBS_USER=/usr/local/lib/R/site-library

WORKDIR /benchmarks
CMD ["/bin/bash"]
