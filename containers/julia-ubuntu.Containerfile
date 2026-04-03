# =============================================================================
# THESIS JULIA ENVIRONMENT - Ubuntu 22.04
# Version: 4.0.0
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        build-essential cmake git wget curl \
        libopenblas-dev \
        gdal-bin libgdal-dev \
        proj-bin libproj-dev \
        libgeos-dev \
        libsqlite3-dev \
        hyperfine time \
    && rm -rf /var/lib/apt/lists/*

ENV JULIA_VERSION=1.11.4
ENV JULIA_PATH=/usr/local/julia
ENV PATH="${JULIA_PATH}/bin:${PATH}"
ENV JULIA_NUM_THREADS=8

RUN wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.11/julia-${JULIA_VERSION}-linux-x86_64.tar.gz && \
    mkdir -p "${JULIA_PATH}" && \
    tar -xzf julia-${JULIA_VERSION}-linux-x86_64.tar.gz -C "${JULIA_PATH}" --strip-components=1 && \
    rm julia-${JULIA_VERSION}-linux-x86_64.tar.gz

RUN julia -e 'using Pkg; \
    Pkg.add(["BenchmarkTools", "CSV", "DataFrames", "SHA", "MAT", \
             "ArchGDAL", "GeoDataFrames", "LibGEOS", "NearestNeighbors", \
             "Shapefile", "JSON3", "Rasters"]); \
    Pkg.precompile()'

WORKDIR /workspace
COPY . .

CMD ["/bin/bash"]
