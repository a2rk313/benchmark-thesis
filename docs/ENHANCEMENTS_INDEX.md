# Benchmark Suite v2.0 Documentation Index

## Quick Navigation

| Topic | Document | Description |
|-------|----------|-------------|
| **Getting Started** | | |
| New Features Overview | `STATISTICAL_FEATURES.md` | Comprehensive guide to all v2.0 features |
| Statistical Methods | `STATISTICAL_FEATURES.md` | Median-of-means, normality tests, effect sizes |
| Outlier Handling | `OUTLIER_HANDLING.md` | IQR-based outlier detection methodology |
| Regression Testing | `regression_testing.md` | Detect performance regressions |
| Flaky Test Detection | `detect_flaky.md` | Identify unstable benchmarks |
| Benchmark Diffing | `benchmark_diffing.md` | Compare against baselines |
| Trend Analysis | `trend_analysis.md` | Track performance over time |

---

## New in v2.0

### Statistical Enhancements

| Feature | Function | Purpose |
|---------|----------|---------|
| Median-of-Means | `median_of_means()` | Robust estimator combining efficiency with outlier resistance |
| Shapiro-Wilk | `shapiro_wilk_test()` | Normality test for small samples (n < 50) |
| D'Agostino-Pearson | `dagostino_pearson_test()` | Normality test for medium samples (n >= 50) |
| Jarque-Bera | `jarque_bera_test()` | Normality test for large samples (n >= 2000) |
| Cohen's d | `cohen_d()` | Standardized effect size |
| Glass's Δ | `glass_delta()` | Effect size using control group SD |
| Bonferroni | `bonferroni_correction()` | Multiple comparison correction |
| Benjamini-Hochberg | `benjamini_hochberg_correction()` | FDR-controlling correction |
| Bootstrap CI | `bootstrap_ci()` | Non-parametric confidence intervals |
| Power Analysis | `power_analysis_required_runs()` | Sample size planning |

### New Benchmarks

| Benchmark | File | Description |
|-----------|------|-------------|
| Real MODIS NDVI | `real_modis_timeseries.py` | Downloads real NASA satellite data |
| Parallel Map-Reduce | `parallel_mapreduce.py` | Embarrassingly parallel tile processing |
| Cross-Language | `cross_language_converter.py` | Converts Julia/R output to Python format |

### Quality Assurance Tools

| Tool | File | Purpose |
|------|------|---------|
| Regression Testing | `regression_tests.py` | Hash-based correctness validation |
| Flaky Detection | `detect_flaky.py` | CV-based variance analysis |
| Benchmark Diff | `benchmark_diff.py` | Baseline comparison tool |
| Trend Analysis | `trend_analysis.py` | Performance tracking over time |
| JIT Tracking | `jit_tracking.py` | Julia compilation overhead tracking |

---

## Usage Examples

### Running Tests

```bash
# Run all enhancement tests (38 tests)
python benchmarks/test_enhancements.py

# Run specific test class
python -m pytest benchmarks/test_enhancements.py::TestMedianOfMeans -v
```

### Statistical Analysis

```python
from benchmark_stats import (
    median_of_means,
    cohen_d,
    detect_outliers_iqr,
    bootstrap_ci,
)

# Analyze benchmark results
mom, blocks = median_of_means(times)
effect = cohen_d(python_times, julia_times)
filtered, outliers = detect_outliers_iqr(times)
lower, upper = bootstrap_ci(times)
```

### Cross-Language Compatibility

```bash
# Convert Julia output to Python format
python benchmarks/cross_language_converter.py \
    --julia results/matrix_ops_julia.json \
    --output results/converted/

# Convert R output
python benchmarks/cross_language_converter.py \
    --r results/matrix_ops_R.json \
    --output results/converted/
```

### Quality Assurance

```bash
# Detect flaky benchmarks
python benchmarks/detect_flaky.py results/ --cv-threshold=0.10

# Check for regressions
python benchmarks/regression_tests.py results/

# Compare with baseline
python benchmarks/benchmark_diff.py baseline/ current/ --output=diff.md
```

---

## File Locations

```
benchmarks/
├── benchmark_stats.py          # All statistical functions
├── academic_stats.py           # Academic result formatting
├── test_enhancements.py         # Test suite (38 tests)
├── cross_language_converter.py # Julia/R format converter
├── regression_tests.py          # Hash-based regression detection
├── detect_flaky.py            # Flaky test detection
├── benchmark_diff.py           # Baseline comparison
├── trend_analysis.py          # Performance tracking
├── jit_tracking.py            # Julia JIT tracking
├── real_modis_timeseries.py    # Real satellite data benchmark
└── parallel_mapreduce.py      # Parallel workload benchmark

docs/
├── STATISTICAL_FEATURES.md     # Comprehensive feature guide
├── OUTLIER_HANDLING.md         # Outlier methodology
├── regression_testing.md       # Regression testing guide (this file)
├── detect_flaky.md            # Flaky detection guide
├── benchmark_diffing.md       # Diffing methodology
└── trend_analysis.md          # Trend tracking guide
```

---

## Testing Checklist

Before publishing results, run:

- [ ] `python benchmarks/test_enhancements.py` - All 38 tests pass
- [ ] `python benchmarks/detect_flaky.py results/` - No flaky benchmarks
- [ ] `python benchmarks/regression_tests.py results/` - No regressions detected
- [ ] `python benchmarks/benchmark_diff.py baseline/ current/` - Document any changes

---

## Version Information

- **v2.0 Release Date**: April 2026
- **Python Version**: 3.14+
- **Dependencies**: numpy, scipy, matplotlib, seaborn

---

## Related Documents

- `STATISTICAL_FEATURES.md` - Complete statistical methods documentation
- `OUTLIER_HANDLING.md` - Outlier detection methodology
- `CHANGELOG.md` - Version history
