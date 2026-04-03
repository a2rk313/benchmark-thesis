# =============================================================================
# OPTIMIZED THESIS R ENVIRONMENT – 50-60% smaller
# Version: 4.0.0 (optimized multi-stage build)
# Base: Fedora 43
# R: 4.5
# Expected size: ~1.2-1.5 GB (was 2.97 GB)
# =============================================================================
#
# OPTIMIZATION TECHNIQUES:
# - Multi-stage build (build deps removed)
# - Aggressive cache cleaning
# - Minimal runtime dependencies
# - Layer consolidation
#
# BUILD:  podman build -t thesis-r:4.5-slim -f containers/r-optimized.Containerfile .
# =============================================================================

# ============================================
# STAGE 1: Build stage
# ============================================
FROM fedora:43 AS builder

# Install build dependencies
RUN dnf -y install \
        gcc gcc-c++ make cmake git wget tar bzip2 curl \
        gdal-devel proj-devel geos-devel sqlite-devel udunits2-devel \
        R-core R-core-devel \
        flexiblas flexiblas-devel \
        openblas openblas-devel \
        openssl-devel libcurl-devel libxml2-devel \
        --setopt=install_weak_deps=False \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# R configuration
ENV R_LIBS_SITE=/usr/local/lib/R/site-library

RUN printf '%s\n' \
    'options(repos = c(CRAN = "https://cloud.r-project.org/"))' \
    'options(download.file.method = "wget")' \
    'options(Ncpus = 4L)' \
    'options(blas = "flexiblas")' \
    '.libPaths(c(Sys.getenv("R_LIBS_SITE"), .libPaths()))' \
    > /root/.Rprofile

RUN mkdir -p "${R_LIBS_SITE}" && chmod 755 "${R_LIBS_SITE}"

# Install all R packages in one layer
RUN Rscript - <<'EOF'
# Install from CRAN
install.packages(c("remotes", "jsonlite", "digest", "data.table", 
                   "R.matlab", "FNN"), 
                 repos = "https://cloud.r-project.org/", 
                 lib = Sys.getenv("R_LIBS_SITE"))

# Install terra (specific version)
library(remotes)
remotes::install_version("terra", version = "1.8-29", 
                         repos = "https://cloud.r-project.org/", 
                         upgrade = "never", 
                         lib = Sys.getenv("R_LIBS_SITE"))
EOF

# Clean up R package build artifacts
RUN find "${R_LIBS_SITE}" -name "*.o" -delete && \
    find "${R_LIBS_SITE}" -name "*.so.dSYM" -delete && \
    rm -rf /tmp/* /var/tmp/* /root/.cache

# ============================================
# STAGE 2: Runtime stage
# ============================================
FROM fedora:43

# Install ONLY runtime libraries
RUN dnf -y install \
        R-core \
        flexiblas \
        openblas \
        gdal-libs proj geos sqlite udunits2 \
        openssl libcurl libxml2 \
        hyperfine time \
        --setopt=install_weak_deps=False \
    && dnf clean all \
    && rm -rf /var/cache/dnf/* /tmp/* /var/tmp/*

# Copy R packages from builder
ENV R_LIBS_SITE=/usr/local/lib/R/site-library
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
COPY --from=builder /root/.Rprofile /root/.Rprofile

# Verify installation
RUN Rscript -e 'library(terra); library(data.table); library(FNN); cat("✓ Core packages OK\n")'

# Runtime environment
ENV OMP_NUM_THREADS=1 \
    R_MAX_VSIZE=16G

WORKDIR /benchmarks
CMD ["/bin/bash"]

# Final size: ~1.2-1.5 GB (down from 2.97 GB)
