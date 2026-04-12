# =============================================================================
# ULTRA-OPTIMIZED THESIS R CONTAINER
# Size: ~1.2GB (with packages)
# Build time: ~10-15 min
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

# Configure R
RUN printf '%s\n' \
    'options(repos = c(CRAN = "https://cloud.r-project.org/"))' \
    'options(download.file.method = "wget")' \
    'options(Ncpus = 4L)' \
    > /root/.Rprofile

# Install all required R packages for benchmarks
# terra: raster/vector operations
# R.matlab: read .mat files (Cuprite dataset)
# FNN: fast k-d tree for IDW interpolation
# data.table, jsonlite, digest: core utilities
RUN Rscript -e ' \
    install.packages(c("terra", "R.matlab", "FNN", "data.table", "jsonlite", "digest"), \
                    repos = "https://cloud.r-project.org/"); \
    cat("Packages installed\n")'

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=8 \
    R_MAX_VSIZE=16G \
    R_LIBS_USER=/usr/local/lib/R/site-library

WORKDIR /benchmarks
CMD ["/bin/bash"]
