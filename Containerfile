# 1. BASE LAYER: CentOS Stream 10
FROM quay.io/centos-bootc/centos-bootc:stream10

# 2. SYSTEM SETUP: Repos & Workstation
# We enable CRB (Code Ready Builder) as it is often needed for EPEL packages.
# We REMOVED the Intel Video drivers causing the failure.
RUN dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && dnf config-manager --set-enabled crb \
    && dnf -y group install workstation-product-environment \
    && dnf -y install \
    # --- BENCHMARK UTILITIES ---
    git \
    wget \
    tar \
    stress-ng \
    htop \
    iotop \
    tuned \
    tuned-profiles-cpu-partitioning \
    # --- COMPATIBILITY ---
    xorg-x11-server-Xwayland \
    && dnf clean all

# 3. TOOL LAYER: Pin Pixi (v0.18.0)
ARG PIXI_VERSION=v0.18.0
RUN curl -fsSL https://github.com/prefix-dev/pixi/releases/download/${PIXI_VERSION}/pixi-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C /usr/bin/ pixi

# 4. APP LAYER: Bake the Lab
WORKDIR /opt/gis-benchmarks
COPY pixi.toml .
RUN pixi install --locked

# 5. JULIA LAYER: Strict Pinning
ENV JULIA_DEPOT_PATH=/opt/gis-benchmarks/.julia_depot
ENV JULIA_PROJECT=/opt/gis-benchmarks
RUN mkdir -p $JULIA_DEPOT_PATH && \
    echo '[GDAL]' > LocalPreferences.toml && \
    echo 'libgdal = "/opt/gis-benchmarks/.pixi/envs/default/lib/libgdal.so"' >> LocalPreferences.toml && \
    echo 'libgdal_vendor = "system"' >> LocalPreferences.toml && \
    pixi run julia -e 'using Pkg; Pkg.add([ \
        {name="ArchGDAL", version="0.10.2"}, \
        {name="Shapefile", version="0.10.1"}, \
        {name="YAXArrays", version="0.5.2"}, \
        {name="Zarr", version="0.12.0"}, \
        {name="DuckDB", version="0.9.2"}, \
        {name="DataFrames", version="1.6.1"}, \
        {name="CSV", version="0.10.13"}, \
        {name="BenchmarkTools", version="1.5.0"}, \
        {name="NearestNeighbors", version="0.4.19"}, \
        {name="StaticArrays", version="1.9.3"} \
    ]); Pkg.instantiate(); Pkg.precompile();'

# 6. CONFIG LAYER: Profile Scripts
RUN echo 'export PATH=/opt/gis-benchmarks/.pixi/envs/default/bin:$PATH' > /etc/profile.d/bench-lab.sh \
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
