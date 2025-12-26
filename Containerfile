# 1. BASE: CentOS Stream 10 (The "RHEL 10" Future)
FROM quay.io/centos-bootc/centos-bootc:stream10

# 2. SYSTEM: High-Performance Setup & GNOME Desktop
# We install the 'workstation-product-environment' to ensure the container
# carries the same GUI overhead (GDM, Mutter, Shell) as Windows 10.
RUN dnf -y install 'dnf-command(config-manager)' \
    && dnf config-manager --set-enabled crb \
    && dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && dnf -y group install workstation-product-environment \
    && dnf -y install \
    # Compilers & Build Tools
    gcc gcc-c++ make git wget tar unzip \
    # Performance Monitoring
    stress-ng htop iotop tuned tuned-profiles-cpu-partitioning \
    # System Libs for GIS
    openssl-devel libffi-devel zlib-devel \
    && dnf clean all

# 3. PIXI: The Scientific Package Manager
ENV PIXI_HOME=/usr
RUN curl -fsSL https://pixi.sh/install.sh | bash

# 4. WORKSPACE: Bake the Lab
WORKDIR /opt/gis-benchmarks
COPY pixi.toml .
# Install the exact scientific stack defined in pixi.toml
RUN pixi install

# 5. JULIA: System Integration (Heavy GIS Stack)
# We bake the Julia depot into the image to prevent runtime compilation lag.
ENV JULIA_DEPOT_PATH=/opt/gis-benchmarks/.julia_depot
ENV JULIA_PROJECT=/opt/gis-benchmarks
RUN mkdir -p $JULIA_DEPOT_PATH && \
    # Force Julia to use the Conda/System libraries (prevents binary mismatch)
    echo '[GDAL]' > LocalPreferences.toml && \
    echo 'libgdal = "/opt/gis-benchmarks/.pixi/envs/default/lib/libgdal.so"' >> LocalPreferences.toml && \
    echo 'libgdal_vendor = "system"' >> LocalPreferences.toml && \
    # Pre-install the heavy HSI and Raster libraries
    pixi run julia -e 'using Pkg; Pkg.add([ \
        "ArchGDAL", "Shapefile", "DataFrames", "CSV", \
        "BenchmarkTools", "NearestNeighbors", "MAT", \
        "YAXArrays", "Zarr", "DimensionalData", "Statistics", \
        "Dates", "ImageFiltering" \
    ]); Pkg.instantiate(); Pkg.precompile();'

# 6. CONFIG: Optimizations & Permissions
RUN echo 'export PATH=/opt/gis-benchmarks/.pixi/envs/default/bin:$PATH' > /etc/profile.d/bench-lab.sh \
    && echo 'export JULIA_PROJECT=/opt/gis-benchmarks' >> /etc/profile.d/bench-lab.sh \
    && chmod +x /etc/profile.d/bench-lab.sh \
    && chown -R 1000:1000 /opt/gis-benchmarks \
    && chmod -R 775 /opt/gis-benchmarks \
    # Set CPU to "Throughput Performance" mode to bias towards heavy computation
    && echo "throughput-performance" > /etc/tuned/active_profile

CMD ["pixi", "run", "run-all"]
