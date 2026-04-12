# =============================================================================
# ULTRA-OPTIMIZED THESIS JULIA CONTAINER
# Size: ~800MB (with packages)
# Build time: ~10-15 min
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

# Install Julia packages for benchmarks
RUN julia -e 'using Pkg; \
    Pkg.add(["BenchmarkTools", "CSV", "DataFrames", "SHA", "JSON3", \
             "LibGEOS", "Shapefile", "NearestNeighbors"]); \
    Pkg.precompile()'

# Clean Julia depot
RUN rm -rf /root/.julia/logs \
           /root/.julia/registries/*/.git

ENV JULIA_NUM_THREADS=8 \
    OPENBLAS_NUM_THREADS=8 \
    OMP_NUM_THREADS=8

WORKDIR /benchmarks
CMD ["/bin/bash"]
