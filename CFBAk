# 1. BASE LAYER: CentOS Stream 10
FROM quay.io/centos-bootc/centos-bootc:stream10

# 2. SYSTEM SETUP: Repos & Workstation
RUN dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && dnf config-manager --set-enabled crb \
    && dnf -y group install workstation-product-environment \
    && dnf -y install \
    # --- BENCHMARK UTILITIES ---
    git \
    wget \
    tar \
    unzip \
    stress-ng \
    htop \
    iotop \
    tuned \
    tuned-profiles-cpu-partitioning \
    # --- COMPATIBILITY ---
    xorg-x11-server-Xwayland \
    && dnf clean all

# 3. TOOL LAYER: Install Pixi (Official Script)
ENV PIXI_HOME=/usr
RUN curl -fsSL https://pixi.sh/install.sh | bash

# 4. APP LAYER: Bake the Lab
WORKDIR /opt/gis-benchmarks
COPY pixi.toml .
COPY src ./src
RUN pixi install

# 5. JULIA LAYER: Install Latest GIS Packages
ENV JULIA_DEPOT_PATH=/opt/gis-benchmarks/.julia_depot
ENV JULIA_PROJECT=/opt/gis-benchmarks
RUN mkdir -p $JULIA_DEPOT_PATH && \
    echo '[GDAL]' > LocalPreferences.toml && \
    echo 'libgdal = "/opt/gis-benchmarks/.pixi/envs/default/lib/libgdal.so"' >> LocalPreferences.toml && \
    echo 'libgdal_vendor = "system"' >> LocalPreferences.toml && \
    pixi run julia -e 'using Pkg; Pkg.add([ \
        "ArchGDAL", \
        "Shapefile", \
        "YAXArrays", \
        "Zarr", \
        "DuckDB", \
        "DataFrames", \
        "CSV", \
        "BenchmarkTools", \
        "NearestNeighbors", \
        "StaticArrays" \
    ]); Pkg.instantiate(); Pkg.precompile();'

# 6. CONFIG LAYER: Optimize GNOME & Profile
RUN systemctl mask packagekit.service \
    && systemctl mask plocate-updatedb.service \
    && systemctl mask systemd-oomd \
    && echo 'export PATH=/opt/gis-benchmarks/.pixi/envs/default/bin:$PATH' > /etc/profile.d/bench-lab.sh \
    && echo 'export JULIA_PROJECT=/opt/gis-benchmarks' >> /etc/profile.d/bench-lab.sh \
    && chmod +x /etc/profile.d/bench-lab.sh

# 7. RUNTIME LAYER: Manual Mode Setup
RUN echo "root:benchmark" | chpasswd \
    && chown -R 1000:1000 /opt/gis-benchmarks \
    && chmod -R 775 /opt/gis-benchmarks \
    && systemctl enable gdm \
    && systemctl set-default graphical.target \
    && systemctl enable tuned podman.socket \
    && echo "throughput-performance" > /etc/tuned/active_profile

CMD ["pixi", "run", "run-all"]
