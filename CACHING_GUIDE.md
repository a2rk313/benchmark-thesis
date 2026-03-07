# Container Build Caching Guide

## 🚀 How Caching Works

Container builds use **layer caching** — each instruction in the Containerfile creates a layer that can be reused.

### Layer Caching Example

```dockerfile
# Layer 1: Base image (rarely changes)
FROM fedora:43

# Layer 2: System packages (rarely changes)
RUN dnf install -y gcc python3 ...

# Layer 3: Python packages (rarely changes)
RUN pip install numpy scipy ...

# Layer 4: Copy code (changes frequently)
COPY benchmarks/ /benchmarks/
```

**If only Layer 4 changes:**
- Layers 1-3 reused from cache → FAST (seconds)
- Only Layer 4 rebuilt → Quick

**If Layer 2 changes:**
- Layer 1 reused from cache
- Layers 2-4 rebuilt → SLOW (20+ minutes for scipy)

---

## ⏱️ Build Time Comparison

### With Caching (Default)

**First build (cold):**
```
Time: 20-25 minutes
Why:  scipy builds from source (~10-15 min)
      Everything else: ~10 min
```

**Subsequent builds (no code changes):**
```
Time: 5-10 seconds
Why:  All layers from cache
```

**Subsequent builds (only code changes):**
```
Time: 1-2 minutes
Why:  Layers 1-3 cached, only layer 4 (code copy) rebuilds
```

### Without Caching (--no-cache)

**Every build:**
```
Time: 20-25 minutes
Why:  Everything rebuilt from scratch every time
```

---

## 📋 Scripts & Their Caching Behavior

### `run_benchmarks.sh` (WITH caching)

**Default behavior:** Uses cache

**First run:**
```bash
./run_benchmarks.sh
# Takes: 25 minutes (builds containers from scratch)
```

**Second run:**
```bash
./run_benchmarks.sh
# Takes: 2-3 minutes (uses cached containers, only runs benchmarks)
```

**After editing Containerfile:**
```bash
# Edit containers/python.Containerfile (e.g., add a package)
./run_benchmarks.sh
# Takes: Depends on what changed
#   - Changed package version: 1-2 min (only that layer rebuilds)
#   - Changed system packages: 20-25 min (all subsequent layers rebuild)
```

### `purge_cache_and_rebuild.sh` (Options)

**Option 1: Full rebuild (default, NO caching)**
```bash
./purge_cache_and_rebuild.sh
# Time: 25 minutes
# Use when: Build failures, weird errors, stale cache suspected
```

**Option 2: Cached rebuild (faster)**
```bash
./purge_cache_and_rebuild.sh --cached
# Time: 5 minutes
# Use when: Just want to rebuild after code changes
```

---

## 🎯 When To Use Each Script

### Use `run_benchmarks.sh`

✅ **Normal operation** — run benchmarks
✅ **First time setup** — builds containers automatically
✅ **After code changes** — rebuilds affected layers only
✅ **Daily use** — fast, leverages cache

**Don't use if:** Build is failing (use purge script instead)

### Use `purge_cache_and_rebuild.sh`

✅ **Build failures** — "metadata-generation-failed", "compiler not found"
✅ **Stale cache errors** — "Using cache abc123... ERROR"
✅ **After major changes** — Fedora version, Python version
✅ **Nuclear option** — when nothing else works

**Don't use if:** Build is working (unnecessary, wastes time)

### Use `purge_cache_and_rebuild.sh --cached`

✅ **Clean rebuild** but faster
✅ **After removing old images** but Containerfiles unchanged
✅ **Intermediate option** — between full rebuild and using cache

---

## 🔍 Understanding Build Output

### Cache Hit (Fast)

```
STEP 3/10: RUN dnf install -y gcc python3
--> Using cache abc123def456...
--> abc123def456

STEP 4/10: RUN pip install numpy
--> Using cache 789ghi012jkl...
```

**Interpretation:** Podman found cached layer, reused it (instant!)

### Cache Miss (Slow)

```
STEP 3/10: RUN dnf install -y gcc python3
Fedora 43 - x86_64                        5.2 MB/s |  90 MB     00:17
Installing: gcc python3 ...
Installed: gcc-15.2.1, python3-3.14.0
--> 789ghi012jkl
```

**Interpretation:** Podman rebuilding this layer (takes time)

### Identifying Slow Layers

```
STEP 7/10: RUN pip install scipy
Downloading scipy-1.15.1.tar.gz (59 MB)
Building wheel for scipy: started
Building wheel for scipy: still running...  ← 10+ minutes here!
Building wheel for scipy: finished
```

**Interpretation:** scipy source build is the slow step (~10-15 min)

---

## 🛠️ Manual Cache Control

### Check Current Cache Usage

```bash
# See all thesis images
podman images | grep thesis

# See cache size
podman system df
```

### Selective Cache Clearing

**Clear only dangling images:**
```bash
podman image prune
```

**Clear all unused images:**
```bash
podman image prune -a
```

**Clear build cache only:**
```bash
podman builder prune -a
```

**Nuclear option (everything):**
```bash
podman system prune -af --volumes
```

### Force Rebuild Specific Container

```bash
# Rebuild Python container without cache
podman build --no-cache -t thesis-python:3.13 -f containers/python.Containerfile .

# Rebuild with cache (normal)
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
```

---

## 📊 Cache Size Management

### Disk Space Usage

**Typical sizes:**
```
Fedora base image:      ~500 MB
Python container:       ~2.5 GB (includes scipy, numpy, gdal)
Julia container:        ~2.8 GB (includes ArchGDAL, DataFrames)
R container:           ~2.0 GB (includes terra, sf)

Build cache:           ~1-2 GB (intermediate layers)
Total:                 ~8-10 GB
```

**Your laptop:** 256 GB SSD → 8-10 GB is only 4%! ✅

### When To Clear Cache

**Clear cache if:**
- Disk space < 10 GB free
- Build cache > 5 GB (`podman system df`)
- Old containers accumulating (different versions)

**Keep cache if:**
- Disk space > 50 GB free
- Working on thesis daily (frequent rebuilds)
- Don't want to wait 25 minutes each time

---

## 🚨 Common Cache Problems & Solutions

### Problem: Build fails with "Using cache"

**Symptom:**
```
STEP 7/10: RUN pip install scipy==1.14.1
--> Using cache abc123...
ERROR: Could not find version...
```

**Cause:** Cache contains broken layer from previous failed build

**Solution:**
```bash
./purge_cache_and_rebuild.sh
```

### Problem: Changes not reflected in container

**Symptom:** "I edited the Containerfile but build output is the same"

**Cause:** Layer before your change is cached → podman reuses all layers up to that point

**Solution:**
```bash
# Option 1: Rebuild without cache
podman build --no-cache -t thesis-python:3.13 -f containers/python.Containerfile .

# Option 2: Add dummy layer to force cache invalidation
# Add to Containerfile BEFORE your change:
RUN echo "cache-bust-$(date +%s)" > /dev/null
```

### Problem: "No space left on device"

**Symptom:** Build fails halfway through

**Cause:** Disk full from build cache + containers

**Solution:**
```bash
# Check usage
df -h
podman system df

# Clear everything
podman system prune -af --volumes

# Try again
./run_benchmarks.sh
```

---

## 💡 Best Practices

### Do's ✅

✅ **Use cache by default** — 10-15× faster
✅ **Clear cache when troubleshooting** — use purge script
✅ **Check disk space regularly** — `df -h`
✅ **Use version ranges in Containerfiles** — better cache reuse
✅ **Layer Containerfiles efficiently** — slow things (scipy) in separate layers

### Don'ts ❌

❌ **Don't use --no-cache by default** — wastes time
❌ **Don't keep dozens of old images** — wastes space
❌ **Don't rebuild if build succeeded** — unnecessary
❌ **Don't clear cache daily** — defeats the purpose

---

## 🎓 Advanced: Layer Optimization

### Current Python Containerfile (Optimized)

```dockerfile
# Layer 1: Base (never changes)
FROM fedora:43

# Layer 2: System packages (rarely changes)
RUN dnf install gcc python3 gdal ...

# Layer 3: pip upgrade (rarely changes)
RUN pip install --upgrade pip

# Layer 4: numpy (has wheels, fast)
RUN pip install numpy

# Layer 5: scipy (SOURCE BUILD, slow, separate layer!)
RUN pip install scipy

# Layer 6-8: Other packages (fast)
RUN pip install pandas shapely ...

# Layer 9: Code copy (changes frequently)
COPY benchmarks/ /benchmarks/
```

**Why this is optimal:**
- Slow layer (scipy) isolated
- If scipy cached, rebuilds very fast
- Code changes don't trigger scipy rebuild

### Poor Layering (Don't Do This)

```dockerfile
# BAD: Everything in one layer
RUN pip install numpy scipy pandas shapely geopandas ...
# If ANY package version changes, ALL rebuild (20+ min)

# BAD: Code copy before slow step
COPY benchmarks/ /benchmarks/
RUN pip install scipy
# Every code change triggers scipy rebuild!
```

---

## 📈 Performance Metrics

### Your Laptop (i5-8350U, 16GB RAM, 256GB SSD)

**First build (no cache):**
- Base image download: 2 min
- System packages: 3 min
- Python packages: 12 min (scipy 10 min + others 2 min)
- Julia packages: 5 min
- R packages: 3 min
- **Total: ~25 minutes**

**Subsequent builds (with cache):**
- All cached, no changes: 5-10 seconds
- Code changes only: 1-2 minutes
- Package version bump: 2-5 minutes
- System package change: 20-25 minutes (forces scipy rebuild)

**With purge script (no cache):**
- Same as first build: ~25 minutes

**With purge script --cached:**
- Cache cleared but Containerfiles unchanged: ~5 minutes
- Podman rebuilds but most layers identical → fast

---

## 🎯 Decision Tree

```
Need to build containers?
│
├─ First time ever?
│  └─ Use: ./run_benchmarks.sh
│     Time: 25 min (expected)
│
├─ Build worked before?
│  └─ Use: ./run_benchmarks.sh
│     Time: <2 min (cached)
│
├─ Build failing?
│  ├─ Stale cache suspected?
│  │  └─ Use: ./purge_cache_and_rebuild.sh
│  │     Time: 25 min (full rebuild)
│  │
│  └─ Just need clean slate?
│     └─ Use: ./purge_cache_and_rebuild.sh --cached
│        Time: 5 min (faster)
│
└─ Just edited code?
   └─ Use: ./run_benchmarks.sh
      Time: 1-2 min (only code layer rebuilds)
```

---

## 🔧 Troubleshooting Cache Issues

### Cache Debug Mode

```bash
# See which layers are cached
podman build --progress=plain -t thesis-python:3.13 -f containers/python.Containerfile .
```

Look for:
- `Using cache` → Layer reused (fast)
- No "Using cache" → Layer rebuilt (slow)

### Find Cache-Busting Change

```bash
# Compare current Containerfile to last successful build
git diff containers/python.Containerfile

# Check if system packages changed
podman run --rm fedora:43 rpm -q python3
```

### Verify Cache is Working

```bash
# First build
time podman build -t test:1 -f containers/python.Containerfile .
# Note time: ~25 minutes

# Immediate rebuild (no changes)
time podman build -t test:2 -f containers/python.Containerfile .
# Should be: <10 seconds

# If second build takes 25 min → cache not working!
```

---

## Summary

**Default behavior (fast):**
- ✅ `run_benchmarks.sh` uses cache
- ⏱️ First build: 25 min, subsequent: <2 min
- 💾 Cache size: ~10 GB (4% of your SSD)

**When things break:**
- 🔧 `./purge_cache_and_rebuild.sh` clears everything and rebuilds
- ⏱️ Time: 25 min (one-time fix)

**Quick rebuild:**
- ⚡ `./purge_cache_and_rebuild.sh --cached` faster option
- ⏱️ Time: 5 min (clears images but uses cache)

**Keep cache unless:**
- Build is failing mysteriously
- Disk space critically low (<10 GB free)
- Major version changes (Fedora, Python)

**Your workflow:**
1. First setup: `./run_benchmarks.sh` (25 min)
2. Daily use: `./run_benchmarks.sh` (<2 min)
3. If broken: `./purge_cache_and_rebuild.sh` (25 min)
4. Back to normal: `./run_benchmarks.sh` (<2 min)

**Caching = 10-15× speedup! Use it!** 🚀
