# =============================================================================
# OPTIMIZED THESIS JULIA ENVIRONMENT – 50-60% smaller
# Version: 4.0.0 (optimized multi-stage build)
# Base: Fedora 43
# Julia: 1.11.4
# Expected size: ~2.0-2.5 GB (was 5.08 GB)
# =============================================================================
#
# OPTIMIZATION TECHNIQUES:
# - Multi-stage build (build deps separated)
# - Aggressive depot cleanup
# - Combined package installation
# - Minimal runtime dependencies
#
# BUILD:  podman build -t thesis-julia:1.11-slim -f containers/julia-optimized.Containerfile .
# =============================================================================

# ============================================
# STAGE 1: Build stage
# ============================================
FROM fedora:43 AS builder

# Install build dependencies
RUN dnf -y install \
        gcc gcc-c++ make cmake git wget tar bzip2 \
        openblas openblas-devel \
        gdal-devel proj-devel geos-devel sqlite-devel \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Install Julia
ENV JULIA_MAJOR=1.11 \
    JULIA_VERSION=1.11.4 \
    JULIA_PATH=/usr/local/julia \
    JULIA_DEPOT_PATH=/julia-depot

ENV PATH="${JULIA_PATH}/bin:${PATH}"

RUN JULIA_URL="https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MAJOR}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" && \
    wget -q "${JULIA_URL}" -O /tmp/julia.tar.gz && \
    mkdir -p "${JULIA_PATH}" && \
    tar -xzf /tmp/julia.tar.gz -C "${JULIA_PATH}" --strip-components=1 && \
    rm /tmp/julia.tar.gz

# Install all packages in one layer (faster, smaller)
RUN julia -e 'using Pkg; \
    Pkg.add(["BenchmarkTools", "CSV", "DataFrames", "SHA", "MAT", \
             "ArchGDAL", "GeoDataFrames", "LibGEOS", "NearestNeighbors", \
             "Shapefile", "JSON3"]); \
    Pkg.precompile()'

# Clean up Julia depot (remove build artifacts, git repos, etc.)
RUN rm -rf /julia-depot/logs \
           /julia-depot/compiled/*/ArchGDAL/*/build \
           /julia-depot/packages/*/.*/.git \
           /julia-depot/registries/*/.*/.git \
    && find /julia-depot -name "*.o" -delete \
    && find /julia-depot -name "*.so.build" -delete

# ============================================
# STAGE 2: Runtime stage
# ============================================
FROM fedora:43

# Install ONLY runtime libraries
RUN dnf -y install \
        openblas \
        gdal-libs proj geos sqlite \
        hyperfine time \
    && dnf clean all \
    && rm -rf /var/cache/dnf/* /tmp/* /var/tmp/*

# Copy Julia from builder
COPY --from=builder /usr/local/julia /usr/local/julia
COPY --from=builder /julia-depot /root/.julia

ENV JULIA_PATH=/usr/local/julia \
    JULIA_DEPOT_PATH=/root/.julia \
    PATH="/usr/local/julia/bin:${PATH}"

# Performance configuration
ENV JULIA_NUM_THREADS=auto

# Verify installation
RUN julia -e 'using BenchmarkTools, CSV, DataFrames, SHA, MAT, ArchGDAL, GeoDataFrames, LibGEOS, NearestNeighbors, JSON3, Shapefile; println("✓ All packages OK")'

WORKDIR /benchmarks
CMD ["/bin/bash"]

# Final size: ~2.0-2.5 GB (down from 5.08 GB)
