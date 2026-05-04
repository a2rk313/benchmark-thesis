================================================================================
THESIS BENCHMARK RESULTS SUMMARY
================================================================================

Performance Rankings (by minimum time, deduplicated):
--------------------------------------------------

  Hsi Stream:
    1. Python: 1.1924s (mean: 1.1932s, std: 0.0005s)
    2. Julia: 2.3316s (mean: 2.3616s, std: 0.0180s)
    3. R: 4.4046s (mean: 4.4796s, std: 0.0460s)

  Interpolation Idw:
    1. Python: 3.0667s (mean: 3.0740s, std: 0.0085s)
    2. R: 4.0673s (mean: 4.1268s, std: 0.0408s)
    3. Julia: 4.7203s (mean: 4.7867s, std: 0.0827s)

  Io Ops:
    1. Python: 0.0014s (mean: 0.0014s, std: 0.0000s)
    2. Julia: 0.0015s (mean: 0.0015s, std: 0.0000s)
    3. R: 0.0065s (mean: 0.0080s, std: 0.0020s)

  Matrix Ops:
    1. Python: 0.0254s (mean: 0.0257s, std: 0.0004s)
    2. Julia: 0.0494s (mean: 0.0604s, std: 0.0130s)
    3. R: 0.1818s (mean: 0.1886s, std: 0.0061s)

  Raster Algebra:
    1. Python: 6.7208s (mean: 6.7208s, std: 0.0000s)
    2. Julia: 32.6655s (mean: 32.6655s, std: 0.0000s)
    3. R: 35.5750s (mean: 35.5750s, std: 0.0000s)

  Reprojection:
    1. Python: 0.0011s (mean: 0.0012s, std: 0.0000s)
    2. R: 0.0130s (mean: 0.0153s, std: 0.0011s)
    3. Julia: 25.0594s (mean: 25.0594s, std: 0.0000s)

  Timeseries Ndvi:
    1. Python: 0.0049s (mean: 0.0050s, std: 0.0000s)
    2. Julia: 0.0068s (mean: 0.0071s, std: 0.0007s)
    3. R: 0.2750s (mean: 0.2929s, std: 0.0116s)

  Vector Pip:
    1. Python: 0.6146s (mean: 0.6290s, std: 0.0118s)
    2. Julia: 8.0750s (mean: 8.2432s, std: 0.1458s)
    3. R: 39.2132s (mean: 39.3680s, std: 0.0897s)

  Zonal Stats:
    1. Julia: 0.0028s (mean: 0.0000s, std: 0.0000s)
    2. R: 0.0490s (mean: 0.0675s, std: 0.0334s)
    3. Python: 0.0864s (mean: 0.0886s, std: 0.0017s)


Summary Statistics:
--------------------------------------------------

Benchmark                Python      Julia          R
--------------------------------------------------
hsi_stream               1.1924     2.3316     4.4046
interpolation_idw        3.0667     4.7203     4.0673
io_ops                   0.0014     0.0015     0.0065
matrix_ops               0.0254     0.0494     0.1818
raster_algebra           6.7208    32.6655    35.5750
reprojection             0.0011    25.0594     0.0130
timeseries_ndvi          0.0049     0.0068     0.2750
vector_pip               0.6146     8.0750    39.2132
zonal_stats              0.0864     0.0028     0.0490