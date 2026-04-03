# =============================================================================
# THESIS R ENVIRONMENT – No sf/s2, uses terra for vector ops + FNN + R.matlab
# Version: 2.18.0
# =============================================================================

FROM docker.io/library/fedora:43

LABEL org.opencontainers.image.title="Thesis R Geospatial Lab" \
      org.opencontainers.image.version="4.5-benchmark-ready"

# ---------- Layer 1: Base development tools ----------
RUN dnf -y upgrade --refresh && \
    dnf -y install \
        gcc gcc-c++ make cmake git wget tar bzip2 curl \
        time sysstat hyperfine \
    && dnf clean all

# ---------- Layer 2: Geospatial system libraries ----------
RUN dnf -y install \
        gdal gdal-devel \
        proj proj-devel \
        geos geos-devel \
        sqlite sqlite-devel \
        udunits2-devel \
    && dnf clean all

# ---------- Layer 3: R and optimised BLAS (NO WEAK DEPS) ----------
RUN dnf install -y \
        --setopt=install_weak_deps=False \
        R-core R-core-devel \
        flexiblas flexiblas-devel \
        openblas openblas-devel \
        openssl-devel libcurl-devel libxml2-devel \
    && dnf clean all

# ---------- Configure OpenBLAS as default BLAS ----------
RUN flexiblas set-system OpenBLAS

# ---------- Layer 4: R packages available from Fedora ----------
RUN dnf -y install \
        R-remotes \
        R-jsonlite \
        R-digest \
        R-bench \
        R-data.table \
    && dnf clean all

# ---------- R configuration ----------
ENV R_LIBS_SITE=/usr/local/lib/R/site-library

RUN printf '%s\n' \
    'options(repos = c(CRAN = "https://cloud.r-project.org/"))' \
    'options(download.file.method = "wget")' \
    'options(Ncpus = 4L)' \
    'options(blas = "flexiblas")' \
    '.libPaths(c(Sys.getenv("R_LIBS_SITE"), .libPaths()))' \
    > /root/.Rprofile

RUN mkdir -p "${R_LIBS_SITE}" && chmod 755 "${R_LIBS_SITE}"
RUN Rscript -e "if(file.access(Sys.getenv('R_LIBS_SITE'), 2) != 0) stop('Directory not writable')"
RUN curl -Is https://cloud.r-project.org | head -1 && echo "Network OK" || echo "WARNING: CRAN unreachable"

# ---------- Install terra (pinned version) ----------
RUN Rscript - <<'EOF'
if (!require("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = "https://cloud.r-project.org/", lib = Sys.getenv("R_LIBS_SITE"))
  library(remotes)
}
remotes::install_version("terra", version = "1.8-29", repos = "https://cloud.r-project.org/", upgrade = "never", lib = Sys.getenv("R_LIBS_SITE"))
EOF

# ---------- Install additional CRAN packages for benchmarks ----------
# R.matlab: read .mat files (Cuprite dataset)
# FNN: fast k‑d tree for IDW interpolation
RUN Rscript - <<'EOF'
install.packages(c("R.matlab", "FNN"), repos = "https://cloud.r-project.org/", lib = Sys.getenv("R_LIBS_SITE"))
EOF

# ---------- Verification ----------
RUN Rscript - <<'EOF'
pkgs <- c("terra", "data.table", "jsonlite", "digest", "R.matlab", "FNN")
for (p in pkgs) {
    library(p, character.only = TRUE)
    cat(sprintf("%-12s %s\n", p, as.character(packageVersion(p))))
}
cat("✓ All R packages OK\n")
cat("BLAS: ", sessionInfo()$BLAS, "\n")
EOF

ENV OMP_NUM_THREADS=1 \
    R_MAX_VSIZE=16G

WORKDIR /benchmarks
CMD ["/bin/bash"]
