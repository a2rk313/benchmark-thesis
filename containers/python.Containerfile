# =============================================================================
# THESIS PYTHON ENVIRONMENT – Python 3.13 + uv + compiled stack
# Version: 3.0.0 (compiled, but fast with uv)
# Base: Fedora 43
# =============================================================================
#
# NOTE: This build compiles NumPy/SciPy/Pandas from source (~20–30 minutes).
# Use this only if you absolutely require Python 3.13. For most thesis work,
# the system Python 3.14 (with pre‑built packages) is simpler and equally fair.
#
# BUILD:  podman build -t thesis-python:3.13 -f containers/python.Containerfile .
# =============================================================================

FROM fedora:41

# ---------- Build dependencies and geospatial libraries ----------
RUN dnf install -y \
        # Python 3.13 itself
        python3.13 python3.13-devel \
        # Compilers and BLAS/LAPACK
        gcc gcc-c++ gfortran \
        openblas-devel lapack-devel \
        # Geospatial core (development headers needed for pyproj, fiona, etc.)
        gdal-devel proj-devel geos-devel \
        sqlite-devel \
        # Utilities
        make cmake git wget \
    && dnf clean all

# ---------- Create and activate a virtual environment ----------
RUN python3.13 -m venv /venv
ENV PATH="/venv/bin:$PATH"

# ---------- Install uv (fast package installer) ----------
RUN pip install --upgrade pip wheel setuptools && \
    pip install uv

# ---------- Set environment variables to force OpenBLAS ----------
ENV NPY_BLAS_ORDER=openblas \
    NPY_LAPACK_ORDER=openblas \
    OPENBLAS=/usr/lib64/libopenblas.so

# ---------- Install Python packages (compiled) ----------
# Use uv for speed and reproducibility
RUN uv pip install \
    numpy \
    scipy \
    pandas \
    shapely \
    pyproj \
    fiona \
    rasterio \
    geopandas \
    scikit-learn \
    psutil \
    tqdm \
    matplotlib \
    seaborn \
    h5py

# ---------- Verification ----------
RUN python3 - << 'PYEOF'
import sys
print(f"Python: {sys.version}")
import numpy;       print(f"numpy      {numpy.__version__}")
import scipy;       print(f"scipy      {scipy.__version__}")
import pandas;      print(f"pandas     {pandas.__version__}")
import shapely;     print(f"shapely    {shapely.__version__}")
import pyproj;      print(f"pyproj     {pyproj.__version__}")
import fiona;       print(f"fiona      {fiona.__version__}")
import rasterio;    print(f"rasterio   {rasterio.__version__}")
import geopandas;   print(f"geopandas  {geopandas.__version__}")
import sklearn;     print(f"sklearn    {sklearn.__version__}")
import matplotlib;  print(f"matplotlib {matplotlib.__version__}")
print("✓ All packages OK")
# Check BLAS linkage
import numpy as np
np.show_config()
PYEOF

# ---------- Utilities ----------
RUN dnf install -y hyperfine time sysstat && dnf clean all

# ---------- Runtime ----------
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR \
    GDAL_CACHEMAX=512

WORKDIR /benchmarks
CMD ["/bin/bash"]
