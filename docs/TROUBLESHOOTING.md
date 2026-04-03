# Troubleshooting Guide

## Build Errors

### Error: "gfortran not found" during scipy build

**Symptom:**
```
ERROR: Unknown compiler(s): [['gfortran'], ...]
Running `gfortran --help` gave "[Errno 2] No such file or directory: 'gfortran'"
```

**Cause:** scipy source build (needed for Python 3.14) requires Fortran compiler.

**Solution:**
The Containerfile now installs `gcc-gfortran` and verifies it. If this error still occurs:

1. **Check Fedora version:**
   ```bash
   podman run --rm fedora:43 cat /etc/fedora-release
   ```

2. **Manually verify gfortran package:**
   ```bash
   podman run --rm fedora:43 bash -c "dnf install -y gcc-gfortran && gfortran --version"
   ```

3. **Alternative: Use older Python with scipy wheels:**
   Edit `python.Containerfile`, change:
   ```dockerfile
   FROM docker.io/library/fedora:43
   ```
   to:
   ```dockerfile
   FROM docker.io/library/fedora:42
   ```
   Fedora 42 ships Python 3.13 which has scipy binary wheels (no compilation needed).

---

### Error: "OpenBLAS not found" during scipy build

**Symptom:**
```
Run-time dependency openblas found: NO (tried pkgconfig and cmake)
ERROR: Dependency "OpenBLAS" not found, tried pkgconfig and cmake
```

**Cause:** scipy's meson build system can't find BLAS/LAPACK libraries via pkg-config.

**Solution:** The Containerfile now uses `flexiblas-devel` (Fedora's BLAS/LAPACK provider) which includes proper pkg-config files. If this error persists:

1. **Verify FlexiBLAS is installed:**
   ```bash
   podman run --rm fedora:43 bash -c "dnf install -y flexiblas-devel pkgconf-pkg-config && pkg-config --modversion flexiblas"
   ```
   Should show: `3.3.1` or similar

2. **Check pkg-config can find it:**
   ```bash
   podman run --rm fedora:43 bash -c "dnf install -y flexiblas-devel pkgconf-pkg-config && pkg-config --libs flexiblas"
   ```
   Should show: `-lflexiblas`

3. **Alternative: Use system scipy (faster, pre-built):**
   Edit `containers/python.Containerfile`, add BEFORE pip installs:
   ```dockerfile
   RUN dnf install -y python3-scipy python3-numpy
   ```
   Then skip scipy/numpy in pip install steps (or remove version constraints).

4. **Alternative: Use Fedora 42 (Python 3.13 has scipy wheels):**
   ```dockerfile
   FROM docker.io/library/fedora:42
   ```
   Python 3.13 has scipy binary wheels → no compilation needed!

---

### Error: "No matching distribution found for scipy==X.Y.Z"

**Symptom:**
```
ERROR: Could not find a version that satisfies the requirement scipy==1.15.1
```

**Cause:** Exact version doesn't exist for your Python version.

**Solution:** The Containerfile now uses version ranges (`scipy>=1.14,<1.16`) which lets pip pick the best available version automatically. No action needed.

---

### Error: Build takes >30 minutes and eventually fails

**Symptom:** scipy build runs for 20+ minutes then fails with memory error.

**Cause:** scipy source compilation needs ~4GB RAM.

**Solution:**

1. **Increase container build memory:**
   ```bash
   # For podman
   podman build --memory=6g -t thesis-python:3.13 -f containers/python.Containerfile .
   
   # For docker
   docker build --memory=6g -t thesis-python:3.13 -f containers/python.Containerfile .
   ```

2. **Or use pre-built scipy:**
   Install system scipy first:
   ```dockerfile
   RUN dnf install -y python3-scipy
   ```
   Then skip pip install for scipy.

---

### Error: "Using cache" loads old broken layer

**Symptom:**
```
STEP 7/11: RUN python3 -m pip install ...
--> Using cache abc123...
ERROR: Could not find a version...
```

**Cause:** Podman cached a broken layer from a previous failed build.

**Solution:**

1. **Use the provided purge script:**
   ```bash
   ./purge_cache_and_rebuild.sh
   ```

2. **Or manually:**
   ```bash
   # Remove all thesis images
   podman rmi -f thesis-python:3.13 thesis-julia:1.11 thesis-r:4.5
   
   # Prune all build cache
   podman system prune -af
   
   # Rebuild with --no-cache
   podman build --no-cache -t thesis-python:3.13 -f containers/python.Containerfile .
   ```

---

## Runtime Errors

### Error: Benchmark crashes with "Killed" or OOM

**Symptom:**
```
Killed
```

**Cause:** Container ran out of memory.

**Solution:**

1. **Increase container memory:**
   ```bash
   podman run --memory=8g --rm -v $(pwd):/benchmarks:Z thesis-python:3.13 python3 benchmarks/hsi_stream.py
   ```

2. **Or reduce dataset size:**
   Edit benchmark scripts to use smaller test data.

---

### Error: "Permission denied" when accessing data files

**Symptom:**
```
PermissionError: [Errno 13] Permission denied: '/benchmarks/data/...'
```

**Cause:** SELinux on Fedora blocks container from accessing host files.

**Solution:** Add `:Z` to volume mounts (already in run_benchmarks.sh):
```bash
podman run -v $(pwd):/benchmarks:Z  # ← Note the :Z suffix
```

---

### Error: hyperfine not found

**Symptom:**
```
bash: hyperfine: command not found
```

**Cause:** hyperfine not installed on host system.

**Solution:**

**Option 1 - Cargo install (recommended):**
```bash
cargo install hyperfine
```

**Option 2 - Download binary:**
```bash
wget https://github.com/sharkdp/hyperfine/releases/download/v1.18.0/hyperfine-v1.18.0-x86_64-unknown-linux-gnu.tar.gz
tar -xzf hyperfine-*.tar.gz
sudo cp hyperfine-*/hyperfine /usr/local/bin/
```

**Option 3 - Fedora package:**
```bash
sudo dnf install hyperfine
```

---

## Performance Issues

### Build is very slow (>1 hour)

**Expected:** First build takes 15-30 minutes due to scipy source compilation.

**If >1 hour:**

1. **Check internet speed:**
   ```bash
   curl -o /dev/null http://releases.ubuntu.com/22.04/ubuntu-22.04-desktop-amd64.iso
   ```
   Should show >1 MB/s.

2. **Use local mirror:**
   Add to Containerfile before `dnf` commands:
   ```dockerfile
   RUN echo "fastestmirror=1" >> /etc/dnf/dnf.conf
   ```

3. **Check CPU:**
   scipy compilation is CPU-intensive. On older CPUs (like your i5-8350U), expect 20-30 minutes.

---

### Benchmarks run much slower than expected

**Expected times (warm start, your laptop):**
- Vector: ~10-15 seconds
- Interpolation: ~15-20 seconds
- Time-series: ~5-8 seconds
- Hyperspectral: ~40-60 seconds

**If 2-3× slower:**

1. **Check thermal throttling:**
   ```bash
   watch -n1 'cat /proc/cpuinfo | grep MHz'
   ```
   Should stay above 3000 MHz under load. If dropping to <2000 MHz → thermal throttling.

2. **Check background processes:**
   ```bash
   top
   ```
   Close browsers, IDEs, etc.

3. **Check CPU governor:**
   ```bash
   cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```
   Should be `performance`, not `powersave`.

---

## Container-Specific Issues

### Error: "executable file not found in $PATH"

**Symptom:**
```
Error: executable file not found in $PATH: unknown
```

**Cause:** Container can't find the command (python3, julia, Rscript).

**Solution:** The command is in the container, not host. Make sure you're using:
```bash
podman run --rm -v $(pwd):/benchmarks:Z thesis-python:3.13 python3 script.py
#                                            ↑ Container   ↑ Command
```

Not:
```bash
python3 script.py  # ← This runs on HOST, not in container!
```

---

### Error: "image not found"

**Symptom:**
```
Error: thesis-python:3.13: image not found in local storage
```

**Cause:** Container image not built yet.

**Solution:**
```bash
./purge_cache_and_rebuild.sh
# Or
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
```

---

## Debug Mode

**Enable verbose build output:**
```bash
podman build --no-cache --progress=plain -t thesis-python:3.13 -f containers/python.Containerfile .
```

**Test specific layer:**
```bash
# Build up to a specific step
podman build --no-cache --target <step> ...
```

**Interactive debugging:**
```bash
# Run container with shell
podman run --rm -it -v $(pwd):/benchmarks:Z thesis-python:3.13 /bin/bash

# Inside container, test commands:
python3 --version
pip list
python3 -c "import scipy; print(scipy.__version__)"
```

---

## Getting Help

**Include in bug report:**

1. **System info:**
   ```bash
   cat /etc/fedora-release
   podman --version
   python3 --version
   ```

2. **Full error log:**
   ```bash
   podman build ... 2>&1 | tee build.log
   ```

3. **Container versions:**
   ```bash
   podman images | grep thesis
   ```

4. **Disk space:**
   ```bash
   df -h
   ```
