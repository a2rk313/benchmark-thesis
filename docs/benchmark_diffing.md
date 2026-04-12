# Benchmark Diffing

## Overview

Compare benchmark results against baselines to track performance changes over time.

## Usage

### Compare Two Directories

```bash
python benchmarks/benchmark_diff.py baseline/ current/ --output=diff_report.md
```

### Compare Against Git Commit

```bash
python benchmarks/benchmark_diff.py \
    --git-baseline=HEAD~10 \
    --current=results/ \
    --output=since_commit.md
```

### JSON Output

```bash
python benchmarks/benchmark_diff.py baseline/ current/ --format=json
```

## Thresholds

| Change | Threshold | Classification |
|--------|-----------|----------------|
| Regression | > +5% | Performance degraded |
| Improvement | < -5% | Performance improved |
| Stable | -5% to +5% | No significant change |

## Output Format

```markdown
# Benchmark Diff Report

## Summary
- Total benchmarks: 27
- Regressions: 2
- Improvements: 5
- Stable: 20

## Regressions

| Benchmark | Language | Change | Baseline | Current |
|-----------|----------|--------|---------|---------|
| matrix_ops | python | +8.2% | 0.456s | 0.493s |

## Improvements

| Benchmark | Language | Change | Baseline | Current |
|-----------|----------|--------|---------|---------|
| vector_pip | julia | -12.3% | 0.234s | 0.205s |
```

## Integration

### Pre-commit Hook

```bash
# Check before committing
python benchmarks/benchmark_diff.py baseline/ results/ || echo "Review required"
```

### CI/CD Integration

```yaml
- name: Performance Diff
  run: |
    python benchmarks/benchmark_diff.py \
        --git-baseline=main \
        --current=results/
```
