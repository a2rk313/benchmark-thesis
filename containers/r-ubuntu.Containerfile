# =============================================================================
# THESIS R ENVIRONMENT - Ubuntu 22.04
# Version: 4.0.0
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        r-base r-base-dev \
        libopenblas-dev \
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libsqlite3-dev \
        libudunits2-dev \
        git wget curl \
        hyperfine time \
    && rm -rf /var/lib/apt/lists/*

ENV R_LIBS_SITE=/usr/local/lib/R/site-library
ENV OPENBLAS_NUM_THREADS=8

RUN mkdir -p "${R_LIBS_SITE}" && \
    echo 'options(repos = c(CRAN = "https://cloud.r-project.org/"))' > /etc/R/Rprofile.site && \
    echo 'options(Ncpus = 4L)' >> /etc/R/Rprofile.site

RUN Rscript -e 'install.packages(c("jsonlite", "data.table", "terra", "sf", "R.matlab", "FNN", "remotes"), lib=Sys.getenv("R_LIBS_SITE"))'

WORKDIR /workspace
COPY . .

CMD ["/bin/bash"]
