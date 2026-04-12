# =============================================================================
# ULTRA-OPTIMIZED THESIS JULIA CONTAINER
# Size: ~1.2GB (with packages)
# Build time: ~15-20 min
# =============================================================================

FROM julia:1.11-bookworm

ENV JULIA_VERSION=1.11.9

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-numpy \
    libopenblas-dev \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libsqlite3-dev \
    libspatialindex-dev \
    gdal-bin \
    proj-bin \
    hyperfine \
    time \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# GDAL Python bindings via system package
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-gdal \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Julia packages for benchmarks
RUN julia -e 'using Pkg; \
    Pkg.add(["BenchmarkTools", "CSV", "DataFrames", "SHA", "JSON3", \
             "MAT", "NearestNeighbors", "LibGEOS", "ArchGDAL", "GeoDataFrames"]); \
    Pkg.precompile()'

# Clean Julia depot
RUN rm -rf /root/.julia/logs \
           /root/.julia/registries/*/.git

ENV JULIA_NUM_THREADS=8 \
    OPENBLAS_NUM_THREADS=8 \
    OMP_NUM_THREADS=8 \
    GDAL_DATA=/usr/share/gdal \
    PYTHONPATH=/usr/lib/python3/dist-packages

WORKDIR /benchmarks
CMD ["/bin/bash"]
