# Flaky Test Detection

## Overview

Flaky tests produce inconsistent results even when running the same code on the same hardware. This guide explains how to detect and handle them.

## Detection Method

The `detect_flaky.py` module uses the **Coefficient of Variation (CV)** method:

```
CV = (Standard Deviation / Mean) × 100
```

| CV Range | Classification | Action |
|----------|---------------|--------|
| < 5% | Excellent | Use results confidently |
| 5-10% | Good | Acceptable for thesis |
| 10-20% | Suspicious | Investigate causes |
| > 20% | Flaky | Do not use results |

## Usage

### Basic Detection

```bash
python benchmarks/detect_flaky.py results/
```

### Custom Threshold

```bash
python benchmarks/detect_flaky.py results/ --cv-threshold=0.10
```

### JSON Output

```bash
python benchmarks/detect_flaky.py results/ --output=flaky_report.json
```

## Causes of Flakiness

1. **System-level**: Background processes, thermal throttling
2. **Hardware-level**: CPU frequency scaling, memory pressure
3. **I/O-level**: Disk contention, network variability
4. **Software-level**: Garbage collection, JIT compilation

## Mitigation Strategies

| Cause | Mitigation |
|-------|------------|
| GC pauses | Increase warmup runs |
| CPU scaling | Disable turbo boost, use `cpufreq` |
| I/O variance | Pre-warm filesystem cache |
| Memory pressure | Close other applications |

## Statistical Robustness

Even with flaky results, use robust estimators:

- **Median**: Not affected by outliers
- **Minimum**: Primary metric (Chen & Revels 2016)
- **Median-of-Means**: Combines robustness with efficiency

## Output Format

```json
{
  "flaky_benchmarks": [],
  "suspicious_benchmarks": [],
  "stable_benchmarks": [
    {
      "name": "matrix_ops",
      "language": "python",
      "cv": 0.023,
      "mean": 0.456,
      "std": 0.010,
      "runs": 30
    }
  ]
}
```

## Recommendations

1. **Run benchmarks multiple times** on different days
2. **Document flakiness** in thesis methodology
3. **Use conservative estimates** when flakiness exists
4. **Report CV** alongside timing results
