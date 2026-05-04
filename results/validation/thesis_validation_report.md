================================================================================
CROSS-LANGUAGE VALIDATION REPORT
================================================================================

Total Scenarios Tested: 9
Successfully Validated: 0
Mismatched Scenarios: 4
Insufficient Data: 0

DETAILED RESULTS:
----------------------------------------

Scenario: interpolation_idw
  Status: MISMATCH
  Languages Present: julia, r, python
  MISMATCH DETAILS:
    julia: 0280fc90fe7a4ae7
    r: d69d816ee9514c0b
    python: a09f293f370acf86

Scenario: timeseries_ndvi
  Status: MISMATCH
  Languages Present: r, python, julia
  MISMATCH DETAILS:
    r: 3b34524ec5bc880d
    python: 7d085423ab411cc7
    julia: 56341e7c407901e7

Scenario: hyperspectral_sam
  Status: MISMATCH
  Languages Present: r, julia, python
  MISMATCH DETAILS:
    r: 67b162161bb19c12
    julia: c554533319eb7b78
    python: 98b83c8f005f88d8

Scenario: vector_pip
  Status: MISMATCH
  Languages Present: python, julia, r
  MISMATCH DETAILS:
    python: 1a609d466dcf1fa6
    julia: 9f997c79152495b3
    r: 840b0f9641110e94

METHODOLOGY NOTE:
--------------------
Validation hashes are generated from output data using SHA256 with
consistent sampling across languages. Matching hashes indicate that
computationally identical operations produce bit-identical results.

If hashes don't match, possible causes include:
  • Different PRNG seeds or algorithms
  • Floating-point precision differences
  • Different mathematical libraries
  • Implementation-specific optimizations
