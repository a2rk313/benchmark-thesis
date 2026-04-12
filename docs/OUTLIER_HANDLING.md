# Outlier Handling in Benchmark Analysis

## Overview

This document describes how outliers are detected, handled, and documented in the thesis benchmarking suite.

## When to Consider a Result as an Outlier

### Criteria

A timing measurement should be considered an outlier if:

1. **IQR Method (Standard)**: The value is outside `Q1 - 1.5*IQR` or `Q3 + 1.5*IQR`
2. **Extreme Outliers**: Values outside `Q1 - 3*IQR` or `Q3 + 3*IQR`
3. **Z-Score Method**: |z-score| > 3.0

### Decision Tree

```
Is the timing distribution normal?
├─ Yes → Use z-score method (|z| > 3.0)
└─ No  → Use IQR method (1.5 × IQR)

Is CV > 20%?
├─ Yes → Investigate system factors before discarding
└─ No  → Standard outlier detection is appropriate
```

## Handling Procedures

### Tier 1: Detection

1. Calculate IQR and identify outliers
2. Calculate z-scores as secondary check
3. Log all potential outliers with context

### Tier 2: Investigation

Before discarding outliers, check for:

- [ ] Background processes consuming resources
- [ ] Thermal throttling events
- [ ] Disk I/O contention
- [ ] Memory pressure/swap activity
- [ ] CPU frequency scaling
- [ ] Network activity (if relevant)
- [ ] Anti-virus/software update activity

### Tier 3: Decision

| Situation | Action |
|-----------|--------|
| Outlier due to system issue | Discard, log reason, repeat run |
| Outlier in first 3 runs | Discard (likely warmup issue) |
| Consistent outlier pattern | Investigate benchmark code |
| Random isolated outliers | Keep, report with variance |

## Implementation

The `detect_outliers_iqr()` function in `benchmark_stats.py`:

```python
def detect_outliers_iqr(times: np.ndarray, factor: float = 1.5) -> Tuple[np.ndarray, List[int]]:
    """
    Detect outliers using IQR method.
    
    Args:
        times: Array of timings
        factor: IQR multiplier (1.5 = standard, 3 = extreme)
    
    Returns:
        Tuple of (filtered_array, outlier_indices)
    """
    q75, q25 = np.percentile(times, [75, 25])
    iqr = q75 - q25
    
    lower = q25 - factor * iqr
    upper = q75 + factor * iqr
    
    mask = (times >= lower) & (times <= upper)
    outlier_indices = np.where(~mask)[0].tolist()
    
    return times[mask], outlier_indices
```

## Reporting

All outliers must be reported in the thesis with:

1. **Count**: Number of outliers detected
2. **Percentage**: `outliers / total_runs * 100`
3. **Magnitude**: How far outside the expected range
4. **Reason**: Why the outlier likely occurred (if determinable)
5. **Impact**: Effect on reported statistics

Example reporting:

```
Outliers detected: 2/30 (6.7%)
- Run #5: 1.45s (expected: 0.8-1.2s) - System thermal throttling
- Run #18: 1.38s (expected: 0.8-1.2s) - Background backup process

Reported statistics use all 30 runs. Sensitivity analysis excluding 
outliers shows <2% difference in mean time.
```

## Statistical Robustness

The benchmark suite uses multiple estimators to reduce outlier impact:

1. **Minimum**: Primary metric (Chen & Revels 2016) - robust to outliers
2. **Median**: Robust central tendency
3. **Median-of-Means**: Combines robustness with efficiency
4. **Bootstrap CI**: Non-parametric, handles outliers naturally

## References

- IQR method: Tukey, J.W. (1977). Exploratory Data Analysis.
- Robust statistics: Huber, P.J. (1981). Robust Statistics.
- Benchmark timing: Chen & Revels (2016). Robust benchmarking in noisy environments.
