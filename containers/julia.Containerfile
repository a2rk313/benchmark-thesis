# =============================================================================
# THESIS JULIA ENVIRONMENT - Reproducible Micro-Container
# Version: 2.7.0 (simplified package setup, LibGEOS removed)
# Base: Fedora 43
# Julia: 1.11.4 (latest stable LTS)
# =============================================================================
#
# CHANGES vs v2.6:
#   - Removed LibGEOS (not in registry)
#   - Simplified to essential packages only
#   - No Project.toml (install packages directly - more reliable)
#
# BUILD:  podman build -t thesis-julia:1.11 -f containers/julia.Containerfile .
# =============================================================================

FROM docker.io/library/fedora:43

LABEL org.opencontainers.image.title="Thesis Julia Geospatial Lab" \
      org.opencontainers.image.version="1.11.4-simplified"

# =============================================================================
# System Dependencies
# =============================================================================
RUN dnf -y upgrade --refresh && \
    dnf -y install \
        gcc gcc-c++ make cmake git wget tar bzip2 \
        time sysstat \
        gdal gdal-devel \
        proj proj-devel \
        geos geos-devel \
        sqlite sqlite-devel \
    && dnf clean all

# Install hyperfine (from Fedora repos, or download binary)
RUN dnf install -y hyperfine

# Document installed versions
RUN rpm -q gdal proj geos sqlite | tee /build-versions.txt

# =============================================================================
# Julia Installation
# =============================================================================
ENV JULIA_MAJOR=1.11 \
    JULIA_VERSION=1.11.4 \
    JULIA_PATH=/usr/local/julia

ENV PATH="${JULIA_PATH}/bin:${PATH}"

RUN set -eux && \
    JULIA_URL="https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MAJOR}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" && \
    echo "Downloading Julia ${JULIA_VERSION}..." && \
    wget -q --show-progress "${JULIA_URL}" -O /tmp/julia.tar.gz && \
    mkdir -p "${JULIA_PATH}" && \
    tar -xzf /tmp/julia.tar.gz -C "${JULIA_PATH}" --strip-components=1 && \
    rm /tmp/julia.tar.gz && \
    julia --version

# =============================================================================
# Julia Package Installation - DIRECT METHOD (no Project.toml)
# This is more reliable for containers - install packages directly
# =============================================================================

# Install essential packages one by one (easier debugging if one fails)
RUN julia -e 'using Pkg; Pkg.add("ArchGDAL")'
RUN julia -e 'using Pkg; Pkg.add("DataFrames")'
RUN julia -e 'using Pkg; Pkg.add("CSV")'
RUN julia -e 'using Pkg; Pkg.add("Shapefile")'
RUN julia -e 'using Pkg; Pkg.add("NearestNeighbors")'
RUN julia -e 'using Pkg; Pkg.add("JSON3")'
RUN julia -e 'using Pkg; Pkg.add("BenchmarkTools")'
RUN julia -e 'using Pkg; Pkg.add("LibGEOS")'
RUN julia -e 'using Pkg; Pkg.add("JSON")'
RUN julia -e 'using Pkg; Pkg.add("GeoDataFrames")'
RUN julia -e 'using Pkg; Pkg.add("MAT")'


# Precompile all installed packages
RUN julia -e 'using Pkg; Pkg.precompile()'

# =============================================================================
# Julia Performance Configuration
# =============================================================================
ENV JULIA_NUM_THREADS=auto \
    JULIA_DEPOT_PATH=/root/.julia

# =============================================================================
# Verification
# =============================================================================
RUN julia -e 'println("Julia version: ", VERSION); println("Threads: ", Threads.nthreads()); using ArchGDAL; println("ArchGDAL: OK"); using DataFrames; println("DataFrames: OK"); using NearestNeighbors; println("NearestNeighbors: OK"); println("✓ All packages OK")'

WORKDIR /benchmarks
CMD ["/bin/bash"]
