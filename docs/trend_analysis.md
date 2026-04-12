# Trend Analysis

## Overview

Track performance changes over multiple benchmark runs to identify long-term trends.

## Usage

### Generate Trend Report

```bash
python benchmarks/trend_analysis.py results/ --output=trends.json
```

### Specify Date Range

```bash
python benchmarks/trend_analysis.py results/ \
    --start=2026-01-01 \
    --end=2026-04-01
```

### Visualize Trends

```bash
python benchmarks/trend_analysis.py results/ --plot --output=trends.png
```

## Metrics Tracked

| Metric | Description |
|--------|-------------|
| Mean time | Average execution time |
| Min time | Best execution time |
| CV | Coefficient of variation |
| Speedup | Relative to first run |

## Trend Detection

The module identifies:

1. **Improving**: Consistent decrease in execution time
2. **Degrading**: Consistent increase in execution time
3. **Stable**: No significant trend
4. **Volatile**: High variance, no clear trend

## Output Format

```json
{
  "trends": {
    "matrix_ops_python": {
      "direction": "improving",
      "slope": -0.002,
      "r_squared": 0.87,
      "p_value": 0.001
    },
    "vector_pip_julia": {
      "direction": "stable",
      "slope": 0.0001,
      "r_squared": 0.12,
      "p_value": 0.45
    }
  },
  "summary": {
    "improving": 3,
    "degrading": 0,
    "stable": 24
  }
}
```

## Use Cases

1. **Hardware changes**: Track impact of system updates
2. **Library updates**: Monitor effect of dependency changes
3. **Code optimizations**: Measure improvement over time
4. **Thesis progress**: Document methodology refinements

## Statistical Significance

Trends are reported with p-values:

- p < 0.05: Statistically significant trend
- p >= 0.05: Trend not significant (may be noise)
