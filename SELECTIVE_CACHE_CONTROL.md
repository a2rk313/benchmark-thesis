# Selective Cache Control - Invalidate Specific Layers

## Understanding Layer Caching

Each `RUN`, `COPY`, `ADD` instruction creates a **layer** that can be cached independently.

```dockerfile
STEP 1: FROM fedora:43           → Layer 1 (base)
STEP 2: RUN dnf install gcc      → Layer 2 (packages)
STEP 3: RUN pip install numpy    → Layer 3 (numpy)
STEP 4: RUN pip install scipy    → Layer 4 (scipy)
STEP 5: COPY benchmarks/ /bench  → Layer 5 (code)
```

**Cache behavior:**
- If Layer 2 changes → Layers 3, 4, 5 rebuild (cache invalidated)
- If Layer 4 changes → Only Layer 5 rebuilds
- If Layer 5 changes → Only Layer 5 rebuilds

**Goal:** Invalidate only the problematic layer, not all layers!

---

## Technique 1: Cache Bust Comment (Recommended)

Add a unique comment **before** the layer you want to rebuild. This invalidates that layer and all subsequent layers.

### Example: Force scipy to rebuild

**Current Containerfile:**
```dockerfile
# Layer 1-6: numpy, pandas, etc. (working, keep cache)
RUN pip install numpy
RUN pip install pandas

# Layer 7: scipy (broken, need to rebuild)
RUN pip install scipy

# Layer 8-10: other packages (working, keep cache)
RUN pip install geopandas
```

**Add cache bust:**
```dockerfile
RUN pip install numpy
RUN pip install pandas

# Cache bust: Force scipy rebuild - 2024-02-24-12:00
RUN pip install scipy

RUN pip install geopandas
```

**Result:**
- Layers 1-6: Use cache ✅
- Layer 7: Rebuild (comment changed) 🔄
- Layers 8-10: Use cache ✅

**When you want to rebuild again, change the comment:**
```dockerfile
# Cache bust: Force scipy rebuild - 2024-02-24-14:30
```

---

## Technique 2: Dummy Layer Method

Add a throwaway `RUN` command with a timestamp to force cache invalidation at a specific point.

```dockerfile
# Packages that are working (keep cache)
RUN pip install numpy pandas

# Cache buster - change this line to force rebuild from here down
RUN echo "rebuild-marker-20240224-1200" > /dev/null

# Everything below this will rebuild when you change the marker
RUN pip install scipy
RUN pip install geopandas
```

**To invalidate:**
```dockerfile
RUN echo "rebuild-marker-20240224-1430" > /dev/null
```

**Cleanup after successful build:**
```dockerfile
# Remove the dummy layer once build succeeds
# (Keep it commented for next time you need it)
```

---

## Technique 3: Change Package Version Constraint

Podman/Docker detects changes in the RUN command text.

**Current (cached):**
```dockerfile
RUN pip install "scipy>=1.14,<1.16"
```

**Force rebuild by changing constraint:**
```dockerfile
RUN pip install "scipy>=1.14.0,<1.16"  # Added .0 - different command!
```

Even though this installs the same package, the command text differs, so cache is invalidated.

**Restore original after build:**
```dockerfile
RUN pip install "scipy>=1.14,<1.16"  # Back to original
```

---

## Technique 4: ARG-based Cache Busting

Use a build argument that you can change without editing the Containerfile.

**Containerfile:**
```dockerfile
# Add at top
ARG CACHE_BUST=1

# Use before layers you want to control
RUN echo "Cache bust: ${CACHE_BUST}"
RUN pip install scipy
```

**Build with different CACHE_BUST values:**
```bash
# First build
podman build --build-arg CACHE_BUST=1 -t thesis-python:3.13 -f containers/python.Containerfile .

# Force scipy layer rebuild (change ARG value)
podman build --build-arg CACHE_BUST=2 -t thesis-python:3.13 -f containers/python.Containerfile .

# Use cache again (same ARG value)
podman build --build-arg CACHE_BUST=2 -t thesis-python:3.13 -f containers/python.Containerfile .
```

**Pro:** No Containerfile edits needed
**Con:** Need to remember ARG values

---

## Technique 5: Layer Splitting for Fine Control

Split problematic layers into separate steps so you can rebuild just one.

**Before (single layer - all or nothing):**
```dockerfile
RUN pip install numpy scipy pandas shapely geopandas
# If scipy fails, entire layer cache is invalid
```

**After (separate layers - fine control):**
```dockerfile
RUN pip install numpy
RUN pip install scipy     # Only this layer needs rebuild
RUN pip install pandas
RUN pip install shapely
RUN pip install geopandas
```

**Benefit:** Can invalidate just the scipy layer

**Your current Python Containerfile already does this!** ✅

---

## Technique 6: Conditional Cache Clearing

Create a script that selectively removes cached layers.

```bash
#!/bin/bash
# selective_purge.sh

# Remove only Python container images (keep Julia/R cache)
podman rmi -f thesis-python:3.13

# Remove only dangling images (incomplete builds)
podman image prune -f

# Don't touch build cache or other containers
# Rebuild Python only - uses cache for unchanged layers
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
```

**Result:** Python rebuilds from cache (fast), Julia/R untouched

---

## Practical Examples

### Example 1: scipy Installation Failed, Fix and Rebuild

**Problem:** scipy layer failed, but numpy/pandas before it are fine.

**Solution:** Add cache bust **before** scipy layer only

```dockerfile
# These work fine - keep cache
RUN pip install numpy
RUN pip install pandas

# CACHE BUST: scipy fix attempt 1
RUN pip install scipy  # Changed approach to system package

# These work fine - keep cache  
RUN pip install shapely
```

**Build:**
```bash
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
```

**Result:**
- numpy/pandas: cached (instant)
- scipy: rebuilds (~1 min if from system, ~15 min if from source)
- shapely onward: rebuilds (~2 min)
- **Total: ~3-4 min instead of full 25 min rebuild**

---

### Example 2: Changed System Packages, Keep pip Layers

**Problem:** Need to add `gcc-gfortran` to system packages.

**Naive approach:**
```dockerfile
RUN dnf install gcc python3  # Changed - invalidates ALL subsequent layers
RUN pip install numpy         # Rebuilds (unnecessary)
RUN pip install scipy         # Rebuilds (necessary)
```

**Smart approach - split dnf install:**
```dockerfile
# Core packages (rarely change)
RUN dnf install gcc python3 gdal

# Compilers (added later, separate layer)
RUN dnf install gcc-gfortran

# Now pip layers after the new dnf layer
RUN pip install numpy  # Uses cache!
RUN pip install scipy  # Rebuilds (compiler available now)
```

**Alternative - even smarter:**

Actually, since you're using **system scipy** now, you don't need gfortran at all!

```dockerfile
# Just install everything in one dnf layer
RUN dnf install gcc python3 gdal python3-scipy python3-numpy
# No pip install for scipy - already installed!
```

---

### Example 3: Code Changed, Keep All Package Layers

**Problem:** Edited `benchmarks/vector_pip.py`

**Containerfile structure:**
```dockerfile
# Packages (don't change)
RUN pip install numpy scipy pandas geopandas

# Code copy (changes frequently)
COPY benchmarks/ /benchmarks/
```

**Result when code changes:**
- Package layers: cached ✅
- Code copy layer: rebuilds (instant - just file copy)
- **Total rebuild: < 5 seconds**

**Your Containerfiles don't COPY code** - that's intentional!
Code is mounted at runtime via `-v` flag, so code changes don't require rebuilds at all.

---

### Example 4: Update One Package Version, Keep Others

**Problem:** Want to update geopandas to 1.1.0, keep everything else.

**Containerfile:**
```dockerfile
RUN pip install numpy
RUN pip install scipy
RUN pip install pandas
RUN pip install shapely
RUN pip install pyproj
RUN pip install fiona
RUN pip install rasterio

# Cache bust comment before the layer to change
# Update: geopandas 1.0.1 -> 1.1.0 (2024-02-24)
RUN pip install "geopandas>=1.1,<1.2"  # Changed version

RUN pip install scikit-learn
# ... rest unchanged
```

**Result:**
- numpy through rasterio: cached
- geopandas: rebuilds (version changed)
- scikit-learn onward: rebuilds (subsequent layers)
- **Much faster than full rebuild**

---

## When Full Purge IS Necessary

**Use `./purge_cache_and_rebuild.sh` (full purge) when:**

1. **Mysterious errors** - cache corruption suspected
2. **Base image changed** - `FROM fedora:43` → `FROM fedora:42`
3. **Major version changes** - Python 3.13 → 3.14
4. **Stale intermediate containers** - old failed builds cluttering
5. **Disk space critical** - need to free space
6. **"Just to be safe"** - before thesis submission, final deliverable

**Use selective cache control when:**

1. **Fixing a specific package** - just scipy failed
2. **Adding one package** - forgot to install something
3. **Version bump** - update single package version
4. **Code changes** - edited benchmark scripts
5. **Iterative debugging** - trying different solutions
6. **Normal development** - daily workflow

---

## Decision Tree

```
Need to rebuild?
│
├─ All containers? (Python, Julia, R all need changes)
│  └─ Use: ./purge_cache_and_rebuild.sh
│     Time: 18 min (full rebuild)
│
├─ One container? (e.g., just Python)
│  ├─ All layers? (base image changed, major refactor)
│  │  └─ Use: podman rmi thesis-python:3.13 && podman build ...
│  │     Time: 5-25 min (depends on compilation)
│  │
│  └─ One layer? (specific package fix)
│     └─ Use: Cache bust comment + build
│        Time: 1-5 min (only changed layers rebuild)
│
└─ No changes, just want fresh build?
   └─ Use: ./purge_cache_and_rebuild.sh --cached
      Time: 5 min (cache cleared but Containerfile uses cache)
```

---

## Advanced: Manual Layer Identification

**Find which layer is cached:**

```bash
podman build --progress=plain -t thesis-python:3.13 -f containers/python.Containerfile . 2>&1 | grep -E "STEP|Using cache"
```

**Output:**
```
STEP 1/14: FROM fedora:43
--> Using cache abc123
STEP 2/14: RUN dnf install ...
--> Using cache def456
STEP 3/14: RUN pip install numpy
--> Using cache ghi789
STEP 4/14: RUN pip install scipy
Downloading scipy...  ← Not using cache (rebuilding)
```

**Interpretation:** Steps 1-3 use cache, Step 4 rebuilds (and all subsequent steps).

---

## Create Your Own Selective Purge Script

```bash
#!/bin/bash
# selective_rebuild.sh - Rebuild only one container

CONTAINER=$1  # python, julia, or r

case $CONTAINER in
  python)
    echo "Rebuilding Python container only..."
    podman rmi -f thesis-python:3.13
    podman build -t thesis-python:3.13 -f containers/python.Containerfile .
    ;;
  julia)
    echo "Rebuilding Julia container only..."
    podman rmi -f thesis-julia:1.11
    podman build -t thesis-julia:1.11 -f containers/julia.Containerfile .
    ;;
  r)
    echo "Rebuilding R container only..."
    podman rmi -f thesis-r:4.5
    podman build -t thesis-r:4.5 -f containers/r.Containerfile .
    ;;
  *)
    echo "Usage: $0 {python|julia|r}"
    exit 1
    ;;
esac
```

**Usage:**
```bash
chmod +x selective_rebuild.sh
./selective_rebuild.sh python  # Rebuild Python only, keep Julia/R
```

---

## Summary Table

| Technique | Invasiveness | Speed | Use Case |
|-----------|--------------|-------|----------|
| **Cache bust comment** | Low | Fast | Single layer fix |
| **Dummy layer** | Medium | Fast | Temporary debugging |
| **Version constraint tweak** | Low | Fast | Force package update |
| **ARG-based** | Low | Fast | No Containerfile edits |
| **Layer splitting** | High (one-time) | Fast (ongoing) | Fine-grained control |
| **Remove single image** | Medium | Medium | One container rebuild |
| **Full purge script** | High | Slow | Nuclear option |

---

## Best Practice: Layer Ordering

**Optimal layer order (slow → fast changing):**

```dockerfile
# 1. Base image (never changes)
FROM fedora:43

# 2. System packages (rarely change)
RUN dnf install gcc python3 gdal ...

# 3. Language runtime (rarely changes)
RUN pip install --upgrade pip

# 4. Core dependencies (rarely change)
RUN pip install numpy scipy pandas

# 5. Application dependencies (occasionally change)
RUN pip install geopandas rasterio shapely

# 6. Development tools (occasionally change)
RUN pip install pytest black flake8

# 7. Code copy (frequently changes) - OR SKIP ENTIRELY
# COPY benchmarks/ /benchmarks/  ← We skip this, mount at runtime instead
```

**Why this order?**
- Changes to layer N only invalidate layers N+1, N+2, ...
- Putting slow-changing things first minimizes rebuilds

---

## Your Current Setup (Already Optimized!)

Your Containerfiles **already follow best practices:**

✅ **Python:** Layered by package groups
```dockerfile
RUN pip install numpy        # Layer 1
RUN pip install scipy        # Layer 2 (can invalidate independently)
RUN pip install pandas       # Layer 3
```

✅ **No code COPY:** Benchmarks mounted at runtime
```bash
podman run -v $(pwd):/benchmarks ...  # Code changes don't trigger rebuilds!
```

✅ **System packages first:** Slow-changing stuff at top

**You're already set up for selective cache control!**

---

## Quick Reference Commands

```bash
# See what's cached
podman images

# Remove one container
podman rmi thesis-python:3.13

# Remove dangling images only
podman image prune

# Remove all unused images
podman image prune -a

# See cache usage
podman system df

# Full cache clear
podman system prune -af

# Build with verbose output (see cache hits)
podman build --progress=plain ...
```

---

## Bottom Line

**Instead of:**
```bash
./purge_cache_and_rebuild.sh  # 18 minutes
```

**Do this:**
```bash
# 1. Add cache bust comment before problem layer
# 2. Build normally
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
# Time: 1-5 min (only changed layers rebuild)
```

**Even better for single container:**
```bash
# Remove just that image, rebuild uses cache
podman rmi thesis-python:3.13
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
```

**Your containers are already optimized for selective invalidation!** 🎯
