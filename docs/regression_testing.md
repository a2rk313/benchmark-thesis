# Regression Testing Guide

## Overview

Regression testing ensures that benchmark performance doesn't degrade between runs or commits.

## Implementation

The `regression_tests.py` module provides hash-based correctness validation and timing consistency checks.

## Usage

### Basic Regression Check

```bash
python benchmarks/regression_tests.py results/
```

### Update Baseline (After Validating Results)

```bash
python benchmarks/regression_tests.py results/ --export
```

### Compare Specific Runs

```bash
python benchmarks/regression_tests.py results/ \
    --baseline results/baseline_2026_01/ \
    --current results/run_2026_04/
```

## Hash Validation

Every benchmark generates a hash of its output data. If the hash changes, it indicates:

1. **Output data changed** (potential correctness issue)
2. **Input data changed** (may be intentional)
3. **Algorithm changed** (should be reviewed)

## Timing Validation

Timing results are validated against expected tolerances:

- **CV threshold**: Default 10% (configurable)
- **Min/Max bounds**: Results outside 3σ are flagged
- **Trend detection**: Identifies gradual degradation

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All validations passed |
| 1 | Hash mismatch detected |
| 2 | Timing validation failed |
| 3 | Flaky benchmark detected |

## Integration with CI/CD

Add to your GitHub Actions workflow:

```yaml
- name: Regression Test
  run: python benchmarks/regression_tests.py results/ || exit 0
```

Use `|| exit 0` for informational runs that shouldn't block merges.
