# Comparison with Tedesco et al. (2025)

## Reference Paper

**Title**: Computational Benchmark Study in Spatio-Temporal Statistics  
**Authors**: Lorenzo Tedesco, Jacopo Rodeschini, Philipp Otto  
**Journal**: Environmetrics (2025)  
**DOI**: 10.1002/env.70017

## Methodology

Both studies use matrix operations to benchmark programming language performance:
- Matrix size: 2500×2500 (k=1 in Tedesco et al.)
- Metrics: Minimum execution time (Chen & Revels 2016 methodology)
- Languages: Python (NumPy), Julia, R (OpenBLAS when available)

## Results Summary

### Cross-Product (A'A)
| Language | Your Result | Tedesco et al. | Ratio | Consistent? |
|----------|-------------|----------------|-------|-------------|
| Python | 0.1638s | 0.0330s | 4.96× | ⚠ |
| Julia | 0.1600s | 0.1820s | 0.88× | ✓ |
| R | 9.8058s | 0.0340s | 288.41× | ⚠ |

### Matrix Determinant
| Language | Your Result | Tedesco et al. | Ratio | Consistent? |
|----------|-------------|----------------|-------|-------------|
| Python | 0.1884s | 0.1180s | 1.60× | ✓ |
| Julia | 0.1374s | 0.1520s | 0.90× | ✓ |
| R | 3.5503s | 0.0440s | 80.69× | ⚠ |

### Sorting (1M values)
| Language | Your Result | Tedesco et al. | Ratio | Consistent? |
|----------|-------------|----------------|-------|-------------|
| Python | 0.0150s | 0.0070s | 2.15× | ⚠ |
| Julia | 0.0265s | 0.0310s | 0.86× | ✓ |
| R | 0.0848s | 0.0770s | 1.10× | ✓ |

## Interpretation

**Ratio Interpretation:**
- Ratio < 1.0: Your hardware is faster
- Ratio ≈ 1.0: Similar performance (validates Tedesco et al.)
- Ratio > 1.0: Your hardware is slower

**Key Finding:** Ratios in the range [0.5, 2.0] are typical and expected due to 
hardware differences (CPU model, RAM speed, BLAS library implementation).

**Most Important:** Language RANKINGS should match, not absolute times.

## Conclusion

Your results {validate/partially validate/differ from} the findings of Tedesco et al. (2025).

*Note: Fill in conclusion based on actual results observed.*
