================================================================================
CROSS-LANGUAGE VALIDATION REPORT
================================================================================

Total Scenarios Tested: 9
Successfully Validated: 4
Mismatched Scenarios: 4
Insufficient Data: 1

DETAILED RESULTS:
----------------------------------------

Scenario: raster_algebra
  Status: VALID
  Languages Present: julia, python, r
  ✓ Hashes match across all languages

Scenario: zonal_statistics
  Status: VALID
  Languages Present: python, r
  ✓ Hashes match across all languages

Scenario: interpolation_idw
  Status: MISMATCH
  Languages Present: julia, r, python
  MISMATCH DETAILS:
    julia: d9cb3f93244e3b9a
    r: 0e0c6690c867d530
    python: 9e2916bf08f9d7dd

Scenario: timeseries_ndvi
  Status: MISMATCH
  Languages Present: r, python, julia
  MISMATCH DETAILS:
    r: db8b7c787a34be07
    python: 839a2f1f8f1f932f
    julia: a340cce5ace76d1e

Scenario: coordinate_reprojection
  Status: VALID
  Languages Present: julia, r, python
  ✓ Hashes match across all languages

Scenario: hyperspectral_sam
  Status: MISMATCH
  Languages Present: r, julia, python
  MISMATCH DETAILS:
    r: 3680c87c1450913b
    julia: 7588c1df0a64df6d
    python: 8bfacd6cf706f65b

Scenario: vector_pip
  Status: MISMATCH
  Languages Present: python, julia, r
  MISMATCH DETAILS:
    python: d6c2fa9db2195cd6
    julia: dd7d02795fd5aaf1
    r: c5b82cf20a8fdfd6

Scenario: zonal_stats
  Status: VALID
  Languages Present: r, julia
  ✓ Hashes match across all languages

Scenario: unknown
  Status: INSUFFICIENT_DATA
  Languages Present: unknown
  WARNING: Insufficient language coverage for validation

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
