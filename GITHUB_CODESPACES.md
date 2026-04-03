# Free Cloud Benchmarking with GitHub Codespaces

## Why GitHub Codespaces?

**100% FREE for your thesis:**
- 60 hours/month free (enough for all benchmarking)
- 4-core CPU, 8GB RAM, 32GB storage
- Consistent Ubuntu environment
- No credit card required
- Perfect for multi-platform comparison

---

## Quick Setup

### 1. Push to GitHub
```bash
git push
```

### 2. Launch Codespace
1. Go to your GitHub repo
2. Click **Code** → **Codespaces** → **Create codespace on main**
3. Wait 3-4 minutes for setup (automatic)

### 3. Run Benchmarks

**Option A: Native mode (faster)**
```bash
./run_benchmarks.sh --native-only
```

**Option B: Container mode (recommended)**
```bash
./run_benchmarks.sh
```

### 4. Download Results
```bash
# Create archive
tar -czf results.tar.gz results/

# Or right-click results/ → Download
```

---

## Setup Details

### Automatic Setup (.devcontainer/setup.sh)
When Codespace starts, these run automatically:
1. Install podman (container runtime)
2. Install hyperfine (benchmarking tool)
3. Download all benchmark datasets
4. Make scripts executable

### Manual Setup (if needed)
```bash
# If data download failed
./.devcontainer/codespaces_setup.sh

# Verify system
./check_system.sh
```

---

## Directory Structure in Codespaces

```
thesis-benchmarks/
├── benchmarks/           # Python, Julia, R scripts
├── tools/               # Unified scripts
│   ├── download_data.py  # Downloads all datasets
│   └── thesis_viz.py     # Visualizations
├── validation/          # Validation suite
│   └── thesis_validation.py
├── containers/           # Dockerfiles
├── data/                # Downloaded datasets
├── results/             # Benchmark outputs
└── run_benchmarks.sh    # Main runner
```

---

## Benchmark Datasets

Automatically downloaded by `tools/download_data.py`:

| Dataset | Size | Description |
|---------|------|-------------|
| AVIRIS Cuprite | ~200MB | Hyperspectral imagery |
| SRTM DEM | ~50MB | Digital elevation model |
| Natural Earth | ~10MB | Vector boundaries |
| Synthetic | Generated | Time series, MODIS |

---

## Commands Reference

```bash
# Check system setup
./check_system.sh

# Run benchmarks (native)
./run_benchmarks.sh --native-only

# Run benchmarks (containers)
./run_benchmarks.sh

# Download data only
python3 tools/download_data.py --all --synthetic

# Generate visualizations
python3 tools/thesis_viz.py --all

# Run validation
python3 validation/thesis_validation.py --all
```

---

## Time Estimates

| Mode | Time | Core-hours |
|------|------|-----------|
| Native only | ~45 min | ~3 |
| Container build | ~15 min | ~1 |
| Full suite (containers) | ~1.5 hrs | ~6 |
| **Total (recommended)** | **~2 hrs** | **~8** |

---

## Troubleshooting

### "Podman not working"
```bash
# Use docker instead
sed -i 's/podman/docker/g' run_benchmarks.sh
```

### "Out of space"
```bash
docker system prune -a
# or
podman system prune -a
```

### "Download failed"
```bash
# Re-run download
python3 tools/download_data.py --all --synthetic
```

### "Permission denied"
```bash
chmod +x *.sh
chmod +x .devcontainer/*.sh
```

---

## Multi-Platform Comparison

Compare with your laptop results:

| Node | Platform | CPU | RAM |
|------|----------|-----|-----|
| Your Laptop | Edge | i5-8350U (4C) | 16GB |
| Codespaces | Cloud | 4 vCPUs | 8GB |

**Perfect for RQ3: Performance Portability!**

---

## Storage Limits

- Codespaces: 32GB total
- Containers: ~3GB
- Data: ~300MB
- Results: ~100MB
- **Used: ~4GB** (plenty of room)

---

## Free Hours

GitHub provides **60 hours/month FREE**

- First run: ~2 hours
- Remaining: 58 hours
- **Tip:** Stop Codespace when done to save hours!

---

## Defense Talking Point

> "Benchmarks were executed on two distinct platforms: a mobile 
> edge device (laptop) and a cloud environment (GitHub Codespaces). 
> This dual-platform approach validates performance portability across 
> different hardware configurations."
