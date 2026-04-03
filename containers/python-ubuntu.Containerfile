# =============================================================================
# THESIS PYTHON ENVIRONMENT - Ubuntu 22.04
# Version: 4.0.0
# For GitHub Codespaces and Ubuntu systems
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        python3.11 python3.11-dev python3-pip \
        python3.11-venv \
        libopenblas-dev liblapack-dev \
        gdal-bin libgdal-dev \
        proj-bin libproj-dev \
        libgeos-dev \
        libsqlite3-dev \
        git wget curl \
        hyperfine time \
    && rm -rf /var/lib/apt/lists/*

ENV OPENBLAS_NUM_THREADS=8
ENV NPY_BLAS_ORDER=openblas
ENV NPY_LAPACK_ORDER=openblas

RUN python3.11 -m venv /venv
ENV PATH="/venv/bin:$PATH"

RUN pip install --upgrade pip wheel && \
    pip install \
        numpy scipy pandas \
        matplotlib rasterio geopandas \
        scikit-learn shapely pyproj fiona \
        h5py rioxarray xarray psutil tqdm seaborn \
        JSON3 BenchmarkTools

WORKDIR /workspace
COPY . .

CMD ["/bin/bash"]
