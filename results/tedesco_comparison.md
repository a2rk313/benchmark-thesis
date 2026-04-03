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
| Python | 0.2345s | 0.0330s | 7.11× | ⚠ |
| Julia | 0.2370s | 0.1820s | 1.30× | ✓ |
| R | 0.2254s | 0.0340s | 6.63× | ⚠ |

### Matrix Determinant
| Language | Your Result | Tedesco et al. | Ratio | Consistent? |
|----------|-------------|----------------|-------|-------------|
| Python | 0.2898s | 0.1180s | 2.46× | ⚠ |
| Julia | 0.2454s | 0.1520s | 1.61× | ✓ |
| R | 0.2960s | 0.0440s | 6.73× | ⚠ |

### Sorting (1M values)
| Language | Your Result | Tedesco et al. | Ratio | Consistent? |
|----------|-------------|----------------|-------|-------------|
| Python | 0.0232s | 0.0070s | 3.31× | ⚠ |
| Julia | 0.0414s | 0.0310s | 1.34× | ✓ |
| R | 0.1460s | 0.0770s | 1.90× | ✓ |

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
