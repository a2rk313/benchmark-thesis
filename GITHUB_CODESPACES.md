# Free Cloud Benchmarking with GitHub Codespaces

## Why GitHub Codespaces?

- 60 hours/month FREE
- 4-core CPU, 8GB RAM, 32GB storage
- Consistent environment
- No credit card required

---

## Quick Setup

### 1. Push Changes
```bash
git push
```
This triggers GitHub Actions to build Fedora containers and push to GHCR.

### 2. Launch Codespace
1. Go to your GitHub repo
2. Click **Code** → **Codespaces** → **Create codespace on main**
3. Wait 3-4 minutes for setup (automatic)

### 3. Run Benchmarks
```bash
# Native mode (uses system Python/Julia/R in Ubuntu)
./run_benchmarks.sh --native-only
```

### 4. Download Results
```bash
tar -czf results.tar.gz results/
```

---

## How It Works

1. **GitHub Actions** builds Fedora containers on every push
2. Containers pushed to **GitHub Container Registry (GHCR)**
3. Codespace pulls containers OR runs natively

## Containers on GHCR

| Tag | Description |
|-----|-------------|
| `thesis-python:fedora` | Python on Fedora 43 |
| `thesis-julia:fedora` | Julia 1.11 on Fedora 43 |
| `thesis-r:fedora` | R 4.5 on Fedora 43 |
| `thesis-*:slim` | Optimized smaller versions |

---

## Commands

```bash
# System check
./check_system.sh

# Native benchmarks
./run_benchmarks.sh --native-only

# Download data only
python3 tools/download_data.py --all --synthetic

# Visualizations
python3 tools/thesis_viz.py --all

# Validation
python3 validation/thesis_validation.py --all
```

---

## Time Estimates

| Mode | Time | Core-hours |
|------|------|-----------|
| Native only | ~45 min | ~3 |
| Container mode | ~1.5 hrs | ~6 |

---

## Troubleshooting

### "Native mode fails"
```bash
# Install dependencies
sudo apt update
sudo apt install python3 python3-pip julia r-base
pip install numpy scipy pandas
```

### "Out of space"
```bash
docker system prune -a
```

---

## Multi-Platform Comparison

| Node | Platform | CPU | RAM |
|------|----------|-----|-----|
| Your Laptop | Edge (Fedora) | i5-8350U | 16GB |
| Codespaces | Cloud (Ubuntu) | 4 vCPUs | 8GB |

Perfect for RQ3: Performance Portability!
