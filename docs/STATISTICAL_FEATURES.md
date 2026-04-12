# Statistical and Analytical Enhancements

## Overview

The benchmark suite now includes **publication-quality statistical analysis and visualization** capabilities, integrating best practices from both the improved methodology (Chapter 3) and the comprehensive tech stack guide.

---

## New Features

### 1. Advanced Statistical Analysis (`validation/statistical_analysis.py`)

**Capabilities:**
- **Normality Testing**: Shapiro-Wilk test for distribution validation
- **Variance Homogeneity**: Levene's test for equal variance assumption
- **Hypothesis Testing**: 
  - Independent t-test (equal variance)
  - Welch's t-test (unequal variance)
  - Mann-Whitney U test (non-parametric)
  - One-way ANOVA (3+ groups)
- **Effect Size Calculations**: Cohen's d with interpretation thresholds
- **Confidence Intervals**: Parametric (95% CI) and bootstrap methods
- **Multiple Comparisons**: Bonferroni correction for ANOVA post-hoc tests
- **Stability Metrics**: Coefficient of variation (CV)

**Usage:**
```bash
python3 validation/statistical_analysis.py
```

**Output:** `results/statistical_analysis.json`

**Example Output Structure:**
```json
{
  "warm_start_analysis": {
    "vector": {
      "pairwise_comparisons": [
        {
          "group1_name": "julia",
          "group2_name": "python",
          "mean1": 5.234,
          "mean2": 12.456,
          "p_value": 0.0001,
          "cohens_d": 2.34,
          "effect_size_interpretation": "Large",
          "speedup": 2.38,
          "test_used": "Welch's t-test (unequal variance)",
          "significant": true
        }
      ]
    }
  }
}
```

---

### 2. Automated Report Generation (`validation/generate_report.py`)

**Capabilities:**
- Comprehensive markdown report with:
  - Executive summary
  - Summary statistics tables
  - Pairwise comparison tables
  - Statistical significance annotations
  - Effect size interpretations
  - Validation cross-checks
  - Practical recommendations
- Easy conversion to PDF/HTML/LaTeX

**Usage:**
```bash
python3 validation/generate_report.py
```

**Output:** `results/reports/benchmark_report.md`

**Sample Report Sections:**

#### Summary Statistics Table
| Language | Mean (s) | Median (s) | Std Dev | Min | Max | CV | 95% CI |
|----------|----------|------------|---------|-----|-----|----|--------|
| Python   | 12.456   | 12.420     | 0.234   | ... | ... | 0.02 | [12.34, 12.57] |
| Julia    | 5.234    | 5.210      | 0.156   | ... | ... | 0.03 | [5.18, 5.29] |
| R        | 8.123    | 8.100      | 0.198   | ... | ... | 0.02 | [8.05, 8.20] |

#### Pairwise Comparison Table
| Comparison | Speedup | Mean Diff (s) | p-value | Significant | Effect Size | Interpretation |
|------------|---------|---------------|---------|-------------|-------------|----------------|
| Julia vs Python | 2.38× | -7.222 | 0.0001 | Yes | 2.34 | Large |
| Julia vs R | 1.55× | -2.889 | 0.0023 | Yes | 1.12 | Large |

---

### 3. Publication-Ready Visualizations (`validation/visualize_results.py`)

**Capabilities:**
- **Performance Comparison Bar Charts**: Mean execution times with error bars
- **Box Plots**: Distribution analysis with outlier detection
- **Speedup Charts**: Relative performance vs. Python baseline
- **Cold vs Warm Comparisons**: Development vs. production trade-offs
- **Memory Usage Charts**: Peak RAM consumption comparison
- All figures at 300 DPI (publication quality)
- Both PNG and PDF (vector) formats

**Usage:**
```bash
python3 validation/visualize_results.py
```

**Output Directory:** `results/figures/`

**Generated Figures:**
- `vector_warm_comparison.png` (and `.pdf`)
- `vector_warm_boxplot.png` (and `.pdf`)
- `vector_warm_speedup.png` (and `.pdf`)
- `vector_cold_vs_warm.png` (and `.pdf`)
- `vector_memory_comparison.png` (and `.pdf`)
- *(Same set for raster scenario)*

**Figure Quality:**
- Resolution: 300 DPI
- Color palette: Colorblind-friendly
- Font: Serif (publication standard)
- Size: Optimized for thesis/paper inclusion

---

## Integrated Statistical Workflow

### Complete Analysis Pipeline

```bash
# 1. Run benchmarks
./run_benchmarks.sh

# This automatically executes:
#   - Cold start benchmarks (development)
#   - Warm start benchmarks (production)
#   - Memory profiling
#   - Correctness validation
#   - Statistical analysis
#   - Report generation
#   - Visualization creation
```

### Manual Analysis Steps

If you need to re-run analysis without re-benchmarking:

```bash
# Statistical analysis
python3 validation/statistical_analysis.py

# Report generation
python3 validation/generate_report.py

# Visualizations
python3 validation/visualize_results.py

# Correctness validation
python3 validation/validate_results.py
```

---

## Statistical Methodology Compliance

### Alignment with Chapter 3 Requirements

| Methodology Requirement | Implementation |
|------------------------|----------------|
| **Effect Size (Cohen's d)** | ✅ Calculated for all pairwise comparisons |
| **Statistical Significance** | ✅ Welch's t-test / Mann-Whitney U |
| **Multiple Comparisons** | ✅ Bonferroni correction in ANOVA |
| **Normality Testing** | ✅ Shapiro-Wilk test |
| **Variance Testing** | ✅ Levene's test |
| **Confidence Intervals** | ✅ 95% CI (parametric + bootstrap) |
| **Stability Metrics** | ✅ Coefficient of variation (CV) |
| **Reproducibility** | ✅ All results saved as JSON |

### Statistical Interpretation Guidelines

#### Effect Size (Cohen's d)
- **|d| < 0.2**: Negligible (differences not practically meaningful)
- **0.2 ≤ |d| < 0.5**: Small (noticeable but minor difference)
- **0.5 ≤ |d| < 0.8**: Medium (substantial difference)
- **|d| ≥ 0.8**: Large (major performance difference)

#### Coefficient of Variation (CV)
- **CV < 0.05**: Highly stable measurements (excellent)
- **0.05 ≤ CV < 0.10**: Acceptable variability (good)
- **CV ≥ 0.10**: High variability (investigate sources of variance)

#### Statistical Significance
- **p < 0.001**: Highly significant (***) 
- **p < 0.01**: Very significant (**)
- **p < 0.05**: Significant (*)
- **p ≥ 0.05**: Not significant (ns)

---

## Using Results in Your Thesis

### Chapter 4: Results

1. **Load the report**: `cat results/reports/benchmark_report.md`
2. **Extract key findings** for narrative description
3. **Include tables** directly from markdown
4. **Reference figures** from `results/figures/`

### Example Thesis Structure

```
4.1 Vector Operations Performance
   - Present summary statistics table
   - Show comparison bar chart (Figure 4.1)
   - Report statistical significance:
     "Julia demonstrated a 2.38× speedup over Python 
      (p < 0.001, d = 2.34, large effect)"
   - Include box plot showing distribution (Figure 4.2)

4.2 Raster Operations Performance
   - [Same structure]

4.3 Cold Start vs Warm Start Analysis
   - Present cold vs warm comparison (Figure 4.5)
   - Discuss two-language problem impact

4.4 Memory Efficiency
   - Present memory comparison chart (Figure 4.9)
   - Calculate memory overhead percentages
```

### Converting Markdown Report to PDF

```bash
# Using pandoc
pandoc results/reports/benchmark_report.md \
    -o thesis_chapter4.pdf \
    --pdf-engine=xelatex \
    --variable geometry:margin=1in

# For LaTeX integration
pandoc results/reports/benchmark_report.md \
    -o thesis_chapter4.tex
```

---

## Thesis Defense Preparation

### Key Talking Points

**1. Statistical Rigor:**
> "I performed comprehensive hypothesis testing using Welch's t-test for pairwise comparisons, with effect sizes calculated using Cohen's d. All comparisons use a significance threshold of α = 0.05."

**2. Effect Sizes:**
> "Julia's speedup over Python showed a large effect size (d = 2.34), indicating not only statistical significance but also practical significance for real-world applications."

**3. Stability:**
> "All measurements achieved a coefficient of variation below 5%, demonstrating highly stable and reproducible results."

**4. Multiple Comparisons:**
> "For the three-language ANOVA, I applied Bonferroni correction to control the family-wise error rate in post-hoc pairwise tests."

---

## Quality Assurance

### Automated Checks Performed

1. **Normality Validation**: Shapiro-Wilk test flags non-normal distributions
2. **Variance Equality**: Levene's test determines appropriate t-test variant
3. **Convergence**: CV thresholds ensure measurement stability
4. **Cross-validation**: All languages must produce identical results (hash check)

### Manual Verification Steps

Before finalizing thesis:

```bash
# 1. Verify all analyses completed
ls results/statistical_analysis.json
ls results/reports/benchmark_report.md
ls results/figures/*.png

# 2. Check for warnings in analysis
grep -i "warning" results/statistical_analysis.json

# 3. Verify figure quality
# Open figures and check:
#   - Readable labels
#   - Appropriate scale
#   - Colorblind-friendly palette
```

---

## Troubleshooting

### Issue: "Insufficient data for comparison"

**Cause:** Less than 2 languages have results for a scenario

**Fix:** Ensure all benchmark scripts ran successfully:
```bash
ls results/warm_start/vector_*_warm.json
```

### Issue: "Cannot find matplotlib module"

**Cause:** Visualization libraries not installed

**Fix:** Rebuild Python container:
```bash
podman build -t thesis-python:3.13 -f containers/python.Containerfile .
```

### Issue: High coefficient of variation (CV > 0.10)

**Cause:** Unstable measurements, possibly due to system load

**Fix:** 
1. Close background applications
2. Increase benchmark iterations:
   - Edit `run_benchmarks.sh`
   - Change `BENCHMARK_RUNS=20` (from 10)

---

## Advanced Usage

### Custom Statistical Tests

Edit `validation/statistical_analysis.py` to add:

```python
# Add your own test
from scipy import stats

def custom_analysis(data1, data2):
    # Example: Permutation test
    result = stats.permutation_test(
        (data1, data2),
        lambda x, y: np.mean(x) - np.mean(y),
        n_resamples=10000
    )
    return result
```

### Custom Visualizations

Edit `validation/visualize_results.py` to create domain-specific plots:

```python
def create_custom_plot(self):
    # Your custom visualization
    fig, ax = plt.subplots(figsize=(10, 6))
    # ... plotting code ...
    plt.savefig(self.figures_dir / "custom_plot.png", dpi=300)
```

---

## Citation in Thesis

When describing your analysis approach in Chapter 3:

> "Statistical analysis was performed using Python 3.14's SciPy library (version 1.14.1). 
> Pairwise comparisons employed Welch's t-test for unequal variances, with effect sizes 
> calculated using Cohen's d (Cohen, 1988). Multiple comparisons were corrected using 
> the Bonferroni method (α/n). All visualizations were generated using Matplotlib (v3.9.3) 
> and Seaborn (v0.13.2) at 300 DPI resolution for publication quality."

---

## Benefits for Your Thesis

✅ **Methodological Rigor**: Proper statistical testing demonstrates understanding of experimental design

✅ **Reproducibility**: Automated pipeline ensures consistent results

✅ **Professional Presentation**: Publication-ready figures and tables

✅ **Thesis Defense Ready**: Can answer statistical methodology questions confidently

✅ **Future Publication**: Reports can be directly adapted for journal submissions

✅ **Time Savings**: Automated report generation vs. manual table creation

---

## Summary Checklist

After running complete benchmark suite, verify:

- [ ] `statistical_analysis.json` exists and contains all scenarios
- [ ] `benchmark_report.md` is complete and readable
- [ ] All figures generated (should have 10+ figures)
- [ ] All effect sizes calculated (check for null values)
- [ ] All p-values < 0.05 where performance differences are claimed
- [ ] Coefficient of variation < 0.05 for all measurements
- [ ] Cross-language validation hashes match (or explained)

**Your thesis now has publication-quality statistical analysis! 🎓📊**

---

## Advanced Statistical Features (v2.0)

### New in Version 2.0

#### 1. Enhanced Statistical Methods (`benchmarks/benchmark_stats.py`)

**New Estimators:**
- **Median-of-Means**: Robust alternative to mean, combines efficiency with outlier resistance
  ```python
  from benchmark_stats import median_of_means
  mom, blocks = median_of_means(times)  # Returns (value, n_blocks)
  ```

- **Multiple Normality Tests**: 
  ```python
  from benchmark_stats import shapiro_wilk_test, dagostino_pearson_test, jarque_bera_test
  p_sw, is_normal = shapiro_wilk_test(times)      # Best for n < 50
  p_dp, _ = dagostino_pearson_test(times)         # Best for n >= 50
  p_jb, _ = jarque_bera_test(times)              # Best for n >= 2000
  ```

**Effect Sizes:**
```python
from benchmark_stats import cohen_d, glass_delta

# Cohen's d: standardized mean difference
d = cohen_d(sample1, sample2)
# |d| < 0.2: negligible, 0.2-0.5: small, 0.5-0.8: medium, >= 0.8: large

# Glass's Δ: uses control group SD (better for unequal variances)
delta = glass_delta(control_sample, treatment_sample)
```

**Multiple Comparison Corrections:**
```python
from benchmark_stats import bonferroni_correction, benjamini_hochberg_correction

p_values = [0.01, 0.02, 0.03, 0.04, 0.05]

# Bonferroni: conservative (α/n)
bonf_sig = bonferroni_correction(p_values, alpha=0.05)

# Benjamini-Hochberg: controls FDR, less conservative
rejected, adjusted_p = benjamini_hochberg_correction(p_values, alpha=0.05)
```

#### 2. Power Analysis (`benchmarks/benchmark_stats.py`)

Calculate required sample size for desired statistical power:
```python
from benchmark_stats import power_analysis_required_runs, estimate_ci_width_required_runs

# Required runs for 80% power with d=0.5 effect size
n = power_analysis_required_runs(effect_size=0.5, alpha=0.05, power=0.8)

# Required runs for 5% CI width
n = estimate_ci_width_required_runs(times, target_width_pct=0.05)
```

#### 3. Thread Scaling Analysis

Analyze performance scaling across thread counts:
```python
from benchmark_stats import run_thread_scaling_analysis

results = run_thread_scaling_analysis(
    func=my_benchmark,
    name="matrix_ops",
    language="python",
    thread_counts=[1, 2, 4, 8, 16],
    runs=10
)
# Returns: max_speedup, optimal_threads, efficiency per thread count
```

#### 4. Memory Profiling

Enhanced memory tracking with system-level metrics:
```python
# BenchmarkResult now includes:
result.memory_rss_mb       # Resident Set Size
result.memory_vms_mb       # Virtual Memory Size  
result.allocations_peak    # Peak Python allocations
```

#### 5. Outlier Detection

IQR-based outlier detection with documentation:
```python
from benchmark_stats import detect_outliers_iqr

filtered_times, outlier_indices = detect_outliers_iqr(times, factor=1.5)
# factor=1.5: standard outliers
# factor=3.0: extreme outliers
```

See `docs/OUTLIER_HANDLING.md` for complete methodology.

#### 6. LaTeX Table Generation

Publication-ready tables with booktabs:
```python
from benchmark_stats import generate_latex_table

latex = generate_latex_table(comparison_dict, output_path="table.tex")
# Output includes: \toprule, \midrule, \bottomrule
```

### New Benchmark Scenarios

#### Real MODIS Time Series (`benchmarks/real_modis_timeseries.py`)
Downloads real NASA MODIS NDVI data for authentic benchmarking:
```bash
python3 benchmarks/real_modis_timeseries.py
```

#### Parallel Map-Reduce (`benchmarks/parallel_mapreduce.py`)
Tests embarrassingly parallel workloads (tile processing):
```bash
python3 benchmarks/parallel_mapreduce.py
```

### Quality Assurance Tools

#### Regression Testing (`benchmarks/regression_tests.py`)
Detect performance regressions against baseline:
```bash
python3 benchmarks/regression_tests.py results/ --export  # Update baseline
python3 benchmarks/regression_tests.py results/            # Check against baseline
```

#### Flaky Test Detection (`benchmarks/detect_flaky.py`)
Identify unstable benchmarks with high variance:
```bash
python3 benchmarks/detect_flaky.py results/ --cv-threshold=0.10
```

#### Benchmark Diffing (`benchmarks/benchmark_diff.py`)
Compare against baseline commits:
```bash
python3 benchmarks/benchmark_diff.py baseline/ current/ --output=diff.md
```

#### Trend Analysis (`benchmarks/trend_analysis.py`)
Track performance over time:
```bash
python3 benchmarks/trend_analysis.py results/ --output=trends.json
```

### Julia JIT Tracking (`benchmarks/jit_tracking.py`)

Track Julia's compilation overhead separately:
```bash
python3 benchmarks/jit_tracking.py
# Creates benchmarks/julia_precompile.jl for faster startup
```

### CI/CD Enhancements (`.github/workflows/run_benchmarks_v2.yml`)

- **Data caching**: Downloads cached between runs
- **Full matrix**: Tests Python/Julia/R × Native/Container
- **Baseline comparison**: Optional diff against specified commit
- **Flaky detection**: Automatic variance analysis
