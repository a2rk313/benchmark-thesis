#!/usr/bin/env python3
"""
================================================================================
Data Scaling Benchmark Framework — All 9 Thesis Scenarios
================================================================================

Runs benchmarks at multiple data scales to:
1. Validate algorithmic complexity via log-log regression
2. Identify performance cliffs and memory bottlenecks
3. Improve statistical reliability across input sizes
4. Follow Tedesco et al. (2025) methodology (k=1,2,3,4 scaling factors)
5. Cover all 9 benchmark scenarios across the thesis

Methodology:
  - Minimum time as primary estimator (Chen & Revels 2016)
  - Data generation OUTSIDE timed section (only computation measured)
  - Consistent random seeds for reproducibility at each scale
  - Log-log regression: log(t) = k * log(n) + c, where k = scaling exponent

Output:
  - results/scaling/{scenario}_scaling.json (per-scenario)
  - results/scaling/combined_scaling_summary.json (all scenarios)
================================================================================
"""

import sys
import json
import time
import gc
import warnings
from pathlib import Path

import numpy as np

# Suppress warnings during benchmarking
warnings.filterwarnings("ignore")

# =============================================================================
# Scaling Configurations
# =============================================================================

MATRIX_SCALES = {
    "k1": 500,     # Small
    "k2": 1000,    # Medium
    "k3": 2000,    # Large
    "k4": 3000,    # Extra large
}

MATRIX_SCALES_QUICK = {
    "k1": 250,
    "k2": 500,
    "k3": 750,
    "k4": 1000,
}

VECTOR_SCALES = {
    "small":  100_000,
    "medium": 500_000,
    "large":  1_000_000,
    "xlarge": 3_000_000,
}

VECTOR_SCALES_QUICK = {
    "small":  25_000,
    "medium": 50_000,
    "large":  100_000,
    "xlarge": 250_000,
}

IO_SCALES = {
    "small":  100_000,
    "medium": 500_000,
    "large":  1_000_000,
    "xlarge": 3_000_000,
}

IO_SCALES_QUICK = {
    "small":  25_000,
    "medium": 50_000,
    "large":  100_000,
    "xlarge": 250_000,
}

RASTER_SCALES = {
    "small":  256,     # 256x256 pixels
    "medium": 512,     # 512x512
    "large":  1024,    # 1024x1024
    "xlarge": 2048,    # 2048x2048
}

RASTER_SCALES_QUICK = {
    "small":  128,
    "medium": 256,
    "large":  512,
    "xlarge": 768,
}

GRID_SCALES = {
    "small":  250,     # 250x250 grid
    "medium": 500,     # 500x500
    "large":  750,     # 750x750
    "xlarge": 1000,    # 1000x1000
}

GRID_SCALES_QUICK = {
    "small":  100,
    "medium": 200,
    "large":  300,
    "xlarge": 400,
}

REPROJ_SCALES = {
    "small":  1_000,
    "medium": 10_000,
    "large":  50_000,
    "xlarge": 100_000,
}

REPROJ_SCALES_QUICK = {
    "small":  500,
    "medium": 2_000,
    "large":  5_000,
    "xlarge": 10_000,
}

HYPERSPECTRAL_SCALES = {
    "small":  128,     # 128x128 pixels, 224 bands
    "medium": 256,     # 256x256
    "large":  512,     # 512x512
    "xlarge": 768,     # 768x768
}

HYPERSPECTRAL_SCALES_QUICK = {
    "small":  64,
    "medium": 128,
    "large":  256,
    "xlarge": 384,
}

TIMESERIES_SCALES = {
    "small":  256,     # 256x256 pixels
    "medium": 512,     # 512x512
    "large":  768,     # 768x768
    "xlarge": 1024,    # 1024x1024
}

TIMESERIES_SCALES_QUICK = {
    "small":  128,
    "medium": 256,
    "large":  512,
    "xlarge": 768,
}

ZONAL_SCALES = {
    "small":  256,     # 256x256 raster
    "medium": 512,     # 512x512
    "large":  1024,    # 1024x1024
    "xlarge": 2048,    # 2048x2048
}

ZONAL_SCALES_QUICK = {
    "small":  128,
    "medium": 256,
    "large":  512,
    "xlarge": 768,
}

IDW_POINT_SCALES = {
    "small":  5_000,
    "medium": 20_000,
    "large":  50_000,
    "xlarge": 100_000,
}

IDW_POINT_SCALES_QUICK = {
    "small":  2_000,
    "medium": 5_000,
    "large":  10_000,
    "xlarge": 20_000,
}


# =============================================================================
# Base Scaling Benchmark Class
# =============================================================================

class ScalingBenchmark:
    """Base class for scaling benchmarks with complexity analysis."""

    def __init__(self, name, scales, n_runs=10, unit="elements"):
        self.name = name
        self.scales = scales
        self.n_runs = n_runs
        self.unit = unit
        self.results = {}

    def setup_at_scale(self, scale_name, scale_value):
        """Pre-generate data at given scale (not timed). Override in subclasses."""
        raise NotImplementedError

    def run_at_scale(self, setup_result):
        """Run the timed benchmark operation. Override in subclasses."""
        raise NotImplementedError

    def run_all_scales(self):
        """Run benchmark at all scales with Chen & Revels (2016) methodology."""
        print(f"\n{'='*70}")
        print(f"SCALING BENCHMARK: {self.name}")
        print(f"{'='*70}")

        for scale_name, scale_value in self.scales.items():
            print(f"\n[{scale_name}] Scale: {scale_value:,} {self.unit}")

            gc.collect()
            setup = self.setup_at_scale(scale_name, scale_value)

            times = []
            for run in range(self.n_runs):
                gc.collect()
                elapsed = self.run_at_scale(setup)
                times.append(elapsed)

            self.results[scale_name] = {
                "scale_value": scale_value,
                "min": float(np.min(times)),
                "mean": float(np.mean(times)),
                "median": float(np.median(times)),
                "std": float(np.std(times)),
                "max": float(np.max(times)),
                "cv": float(np.std(times) / np.mean(times)) if np.mean(times) > 0 else 0,
                "all_times": [float(t) for t in times],
            }

            r = self.results[scale_name]
            print(f"  Min: {r['min']:.4f}s (PRIMARY)  |  "
                  f"Mean: {r['mean']:.4f}s ± {r['std']:.4f}s  |  "
                  f"CV: {r['cv']:.2%}")

    def analyze_complexity(self):
        """Analyze algorithmic complexity via log-log regression.

        Model: log(t) = k * log(n) + c
        The scaling exponent k directly indicates algorithmic complexity:
          k ~ 1.0  =>  O(n)       linear
          k ~ 1.0  =>  O(n log n) linearithmic (hard to distinguish from linear)
          k ~ 2.0  =>  O(n^2)     quadratic
          k ~ 2.3  =>  O(n^2.3)   matrix multiplication (Strassen)
          k ~ 3.0  =>  O(n^3)     cubic
        """
        print(f"\n{'='*70}")
        print(f"COMPLEXITY ANALYSIS: {self.name}")
        print(f"{'='*70}")

        scale_names = list(self.scales.keys())
        if len(scale_names) < 2:
            print("  Insufficient scales for complexity analysis")
            return {"k": None, "r_squared": None, "complexity": "Insufficient data"}

        min_times = np.array([self.results[s]["min"] for s in scale_names])
        scale_values = np.array([self.results[s]["scale_value"] for s in scale_names])

        log_times = np.log(min_times)
        log_sizes = np.log(scale_values)

        try:
            coeffs = np.polyfit(log_sizes, log_times, 1)
            k = coeffs[0]
            c = coeffs[1]

            y_pred = k * log_sizes + c
            ss_res = np.sum((log_times - y_pred) ** 2)
            ss_tot = np.sum((log_times - np.mean(log_times)) ** 2)
            r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0.0

            # Classify complexity
            if r_squared < 0.7:
                complexity_label = "Uncertain (R² < 0.7)"
            elif k < 1.1:
                complexity_label = "O(n) — Linear"
            elif k < 1.5:
                complexity_label = "O(n log n) — Linearithmic"
            elif k < 2.2:
                complexity_label = "O(n²) — Quadratic"
            elif k < 2.5:
                complexity_label = "O(n^2.37) — Matrix multiplication"
            elif k < 3.5:
                complexity_label = "O(n³) — Cubic"
            else:
                complexity_label = f"> O(n³) — Super-cubic (k={k:.2f})"

            print(f"\n  Log-Log Regression:")
            print(f"    Scaling exponent (k): {k:.3f}")
            print(f"    Intercept (c):        {c:.3f}")
            print(f"    R²:                   {r_squared:.4f}")
            print(f"    Estimated complexity: {complexity_label}")

            print(f"\n  Pairwise scaling ratios:")
            for i in range(len(scale_names) - 1):
                size_ratio = scale_values[i+1] / scale_values[i]
                time_ratio = min_times[i+1] / min_times[i]
                exp_est = np.log(time_ratio) / np.log(size_ratio) if size_ratio > 1 else 0
                print(f"    {scale_names[i]:>8s} -> {scale_names[i+1]:>8s}:  "
                      f"size = {size_ratio:.1f}x,  time = {time_ratio:.2f}x,  "
                      f"exp ≈ {exp_est:.2f}")

            return {
                "scaling_exponent": round(k, 4),
                "intercept": round(c, 4),
                "r_squared": round(r_squared, 4),
                "complexity_label": complexity_label,
            }

        except Exception:
            print("\n  Warning: Could not perform log-log regression")
            return {"k": None, "r_squared": None, "complexity": "Regression failed"}

    def save_results(self, output_dir=None):
        """Save scaling results to JSON."""
        if output_dir is None:
            output_dir = Path(__file__).parent / "results" / "scaling"
        else:
            output_dir = Path(output_dir)
        output_file = output_dir / f"{self.name}_scaling.json"

        complexity = self.analyze_complexity()

        output = {
            "benchmark": self.name,
            "unit": self.unit,
            "scales": self.scales,
            "n_runs": self.n_runs,
            "methodology": "Chen & Revels (2016): minimum time as primary estimator",
            "complexity_analysis": complexity,
            "results": self.results,
        }

        try:
            output_file.parent.mkdir(parents=True, exist_ok=True)
            with open(output_file, "w") as f:
                json.dump(output, f, indent=2)
            print(f"\n  Results saved: {output_file}")
        except PermissionError:
            fallback = Path("/tmp/thesis_scaling") / f"{self.name}_scaling.json"
            fallback.parent.mkdir(parents=True, exist_ok=True)
            with open(fallback, "w") as f:
                json.dump(output, f, indent=2)
            print(f"\n  Results saved (fallback): {fallback}")
            output_file = fallback

        return output


# =============================================================================
# Scenario 1: Matrix Operations Scaling
# =============================================================================

class MatrixCrossProductScaling(ScalingBenchmark):
    """Matrix cross-product A^T A scaling. Expected: O(n^2.37) to O(n^3)."""

    def __init__(self, quick=False):
        scales = MATRIX_SCALES_QUICK if quick else MATRIX_SCALES
        super().__init__("matrix_crossproduct", scales, n_runs=10, unit="matrix dimension (n)")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        return np.random.randn(n, n).astype(np.float64)

    def run_at_scale(self, A):
        start = time.perf_counter()
        B = A.T @ A
        return time.perf_counter() - start


class MatrixDeterminantScaling(ScalingBenchmark):
    """Matrix determinant via LU decomposition. Expected: O(n^3)."""

    def __init__(self, quick=False):
        scales = MATRIX_SCALES_QUICK if quick else MATRIX_SCALES
        super().__init__("matrix_determinant", scales, n_runs=10, unit="matrix dimension (n)")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        return np.random.randn(n, n).astype(np.float64)

    def run_at_scale(self, A):
        start = time.perf_counter()
        det = np.linalg.det(A)
        return time.perf_counter() - start


class MatrixPowerScaling(ScalingBenchmark):
    """Element-wise matrix power. Expected: O(n^2)."""

    def __init__(self, quick=False):
        scales = MATRIX_SCALES_QUICK if quick else MATRIX_SCALES
        super().__init__("matrix_power", scales, n_runs=10, unit="matrix dimension (n)")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        A = np.random.randn(n, n).astype(np.float64)
        return np.abs(A) / 2.0

    def run_at_scale(self, A):
        start = time.perf_counter()
        B = np.power(A, 10)
        return time.perf_counter() - start


class SortingScaling(ScalingBenchmark):
    """Array sorting. Expected: O(n log n)."""

    def __init__(self, quick=False):
        scales = VECTOR_SCALES_QUICK if quick else VECTOR_SCALES
        super().__init__("sorting", scales, n_runs=10, unit="elements")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        return np.random.randn(n).astype(np.float64)

    def run_at_scale(self, arr):
        start = time.perf_counter()
        np.sort(arr)
        return time.perf_counter() - start


# =============================================================================
# Scenario 2: I/O Operations Scaling
# =============================================================================

class CSVWriteScaling(ScalingBenchmark):
    """CSV write performance. Expected: O(n)."""

    def __init__(self, quick=False):
        scales = IO_SCALES_QUICK if quick else IO_SCALES
        super().__init__("io_csv_write", scales, n_runs=10, unit="rows")

    def setup_at_scale(self, scale_name, n_rows):
        import csv
        np.random.seed(42)
        data = []
        for i in range(n_rows):
            data.append((
                round(np.random.uniform(-90, 90), 6),
                round(np.random.uniform(-180, 180), 6),
                round(float(np.random.randn()), 6),
            ))
        return data

    def run_at_scale(self, data):
        import csv
        output_path = Path("data") / "scaling_test.csv"
        output_path.parent.mkdir(exist_ok=True)
        start = time.perf_counter()
        with open(output_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["lat", "lon", "value"])
            writer.writerows(data)
        elapsed = time.perf_counter() - start
        output_path.unlink(missing_ok=True)
        return elapsed


class BinaryWriteScaling(ScalingBenchmark):
    """Raw binary write performance. Expected: O(n)."""

    def __init__(self, quick=False):
        scales = IO_SCALES_QUICK if quick else IO_SCALES
        super().__init__("io_binary_write", scales, n_runs=10, unit="float64 values")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        return np.random.randn(n).astype(np.float64)

    def run_at_scale(self, arr):
        output_path = Path("data") / "scaling_test.bin"
        output_path.parent.mkdir(exist_ok=True)
        start = time.perf_counter()
        arr.tofile(output_path)
        elapsed = time.perf_counter() - start
        output_path.unlink(missing_ok=True)
        return elapsed


# =============================================================================
# Scenario 3: Hyperspectral SAM Scaling
# =============================================================================

class HyperspectralSAMScaling(ScalingBenchmark):
    """Spectral Angle Mapper on hyperspectral imagery.
    
    Scales spatial extent (rows x cols) while keeping 224 bands fixed.
    Expected: O(pixels * bands) = O(n^2 * 224) = O(n^2).
    """
    N_BANDS = 224
    CHUNK_SIZE = 256

    def __init__(self, quick=False):
        scales = HYPERSPECTRAL_SCALES_QUICK if quick else HYPERSPECTRAL_SCALES
        super().__init__("hyperspectral_sam", scales, n_runs=5, unit="pixels per side (n x n x 224 bands)")

    def setup_at_scale(self, scale_name, n_pixels):
        np.random.seed(42)
        data = np.random.randn(self.N_BANDS, n_pixels, n_pixels).astype(np.float32)
        ref = np.linspace(0.1, 0.9, self.N_BANDS).astype(np.float32)
        ref /= np.linalg.norm(ref)
        return data, ref

def run_at_scale(self, setup_result):
        import time
        data, ref = setup_result
        n_bands, n_rows, n_cols = data.shape
        start = time.perf_counter()

        for row in range(0, n_rows, self.CHUNK_SIZE):
            for col in range(0, n_cols, self.CHUNK_SIZE):
                row_end = min(row + self.CHUNK_SIZE, n_rows)
                col_end = min(col + self.CHUNK_SIZE, n_cols)
                chunk = data[:, row:row_end, col:col_end]
                pixels = chunk.transpose(1, 2, 0).reshape(-1, n_bands)

                dot_product = pixels @ ref
                pixel_norms = np.linalg.norm(pixels, axis=1)
                ref_norm = np.linalg.norm(ref)
                cos_angle = dot_product / (pixel_norms * ref_norm + 1e-8)
                cos_angle = np.clip(cos_angle, -1.0, 1.0)
                angles = np.arccos(cos_angle)

        return time.perf_counter() - start


# =============================================================================
# Scenario 4: Vector Point-in-Polygon Scaling
# =============================================================================

class VectorPipScaling(ScalingBenchmark):
    """Point-in-Polygon spatial join scaling.
    
    Scales number of points against fixed polygon set.
    Expected: O(n log m) with spatial index, O(n*m) without.
    """

    def __init__(self, quick=False):
        scales = VECTOR_SCALES_QUICK if quick else VECTOR_SCALES
        super().__init__("vector_pip", scales, n_runs=5, unit="query points")
        self.polys = None

    def setup_at_scale(self, scale_name, n_points):
        import geopandas as gpd
        import pandas as pd
        from pathlib import Path

        if self.polys is None:
            data_dir = Path(__file__).parent / "data"
            self.polys = gpd.read_file(str(data_dir / "natural_earth_countries.gpkg"))

        np.random.seed(42)
        points_df = pd.DataFrame({
            "lon": np.random.uniform(-180, 180, n_points),
            "lat": np.random.uniform(-90, 90, n_points),
        })
        points = gpd.GeoDataFrame(
            points_df,
            geometry=gpd.points_from_xy(points_df["lon"], points_df["lat"]),
            crs="EPSG:4326",
        )
        return points

    def run_at_scale(self, points):
        start = time.perf_counter()
        joined = gpd.sjoin(points, self.polys, how="inner", predicate="within",
                           lsuffix="_point", rsuffix="_poly")
        elapsed = time.perf_counter() - start
        return elapsed


# =============================================================================
# Scenario 5: IDW Interpolation Scaling
# =============================================================================

class IDWInterpolationScaling(ScalingBenchmark):
    """Inverse Distance Weighting interpolation scaling.
    
    Scales both input points AND grid resolution proportionally.
    Expected: O(grid_points * log(points)) with KD-tree = O(n^2 * log(n)).
    """

    def __init__(self, quick=False):
        scales = IDW_POINT_SCALES_QUICK if quick else IDW_POINT_SCALES
        super().__init__("interpolation_idw", scales, n_runs=5, unit="input points (grid scales proportionally)")

    def setup_at_scale(self, scale_name, n_points):
        from scipy.spatial import cKDTree
        np.random.seed(42)

        # Scale grid resolution proportionally to sqrt of points
        grid_size = max(100, int(np.sqrt(n_points) * 3))

        x = np.random.uniform(0, 1000, n_points)
        y = np.random.uniform(0, 1000, n_points)
        values = (100 * np.sin(x / 200) * np.cos(y / 200) +
                  50 * np.sin(x / 50) +
                  20 * np.random.randn(n_points))
        points = np.column_stack([x, y])

        grid_x, grid_y = np.meshgrid(
            np.linspace(0, 1000, grid_size),
            np.linspace(0, 1000, grid_size),
        )
        grid_points = np.column_stack([grid_x.ravel(), grid_y.ravel()])

        tree = cKDTree(points)
        return tree, values, grid_points, grid_size

    def run_at_scale(self, setup_result):
        tree, values, grid_points, grid_size = setup_result
        start = time.perf_counter()
        distances, indices = tree.query(grid_points, k=12)
        distances = np.maximum(distances, 1e-10)
        weights = 1.0 / (distances ** 2)
        weights /= weights.sum(axis=1, keepdims=True)
        interpolated = (weights * values[indices]).sum(axis=1)
        return time.perf_counter() - start


# =============================================================================
# Scenario 6: Time-Series NDVI Scaling
# =============================================================================

class TimeseriesNDVIVScaling(ScalingBenchmark):
    """NDVI time-series analysis scaling.
    
    Scales spatial extent (rows x cols) with fixed 12 time steps.
    Expected: O(n^2 * t) for statistics, O(n^2) for trend.
    """
    N_DATES = 12

    def __init__(self, quick=False):
        scales = TIMESERIES_SCALES_QUICK if quick else TIMESERIES_SCALES
        super().__init__("timeseries_ndvi", scales, n_runs=5, unit="pixels per side (n x n x 12 dates)")

    def setup_at_scale(self, scale_name, n_pixels):
        np.random.seed(42)
        x = np.linspace(-1, 1, n_pixels)
        y = np.linspace(-1, 1, n_pixels)
        xx, yy = np.meshgrid(x, y)
        base_vegetation = 0.5 * (1 - (xx**2 + yy**2))

        ndvi_stack = np.zeros((self.N_DATES, n_pixels, n_pixels), dtype=np.float32)
        for t in range(self.N_DATES):
            vegetation_level = 0.5 + 0.3 * np.sin(2 * np.pi * t / self.N_DATES)
            red_noise = np.random.normal(0, 0.05, (n_pixels, n_pixels))
            nir_noise = np.random.normal(0, 0.05, (n_pixels, n_pixels))
            red = 0.1 + 0.2 * (1 - base_vegetation * vegetation_level) + red_noise
            nir = 0.3 + 0.5 * base_vegetation * vegetation_level + nir_noise
            epsilon = 1e-6
            ndvi = (nir - red) / (nir + red + epsilon)
            ndvi_stack[t] = np.clip(ndvi, -0.1, 1.0).astype(np.float32)

        return ndvi_stack

    def run_at_scale(self, ndvi_stack):
        n_dates, height, width = ndvi_stack.shape
        start = time.perf_counter()

        mean_ndvi = np.mean(ndvi_stack, axis=0)
        max_ndvi = np.max(ndvi_stack, axis=0)
        min_ndvi = np.min(ndvi_stack, axis=0)

        time_index = np.arange(n_dates).astype(np.float32)
        mean_time = np.mean(time_index)
        denominator = np.sum((time_index - mean_time)**2)
        numerator = np.sum((time_index[:, None, None] - mean_time) * (ndvi_stack - mean_ndvi), axis=0)
        ndvi_trend = numerator / denominator

        growing_season = np.sum(ndvi_stack > 0.3, axis=0)
        amplitude = max_ndvi - min_ndvi

        return time.perf_counter() - start


# =============================================================================
# Scenario 7: Raster Algebra Scaling
# =============================================================================

class RasterAlgebraScaling(ScalingBenchmark):
    """Raster algebra & band math scaling.
    
    Scales raster dimensions. Expected: O(n^2) for all operations.
    """

    def __init__(self, quick=False):
        scales = RASTER_SCALES_QUICK if quick else RASTER_SCALES
        super().__init__("raster_algebra", scales, n_runs=5, unit="pixels per side (n x n)")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        return {
            "green": np.random.rand(n, n).astype(np.float32) * 1000,
            "red":   np.random.rand(n, n).astype(np.float32) * 800,
            "nir":   np.random.rand(n, n).astype(np.float32) * 2000,
            "swir":  np.random.rand(n, n).astype(np.float32) * 1500,
        }

    def run_at_scale(self, bands):
        start = time.perf_counter()

        # NDVI
        numerator = bands["nir"] - bands["red"]
        denominator = bands["nir"] + bands["red"]
        ndvi = np.where(denominator != 0, numerator / denominator, 0)

        # Band arithmetic
        total = bands["green"] + bands["red"] + bands["nir"] + bands["swir"]
        diff = bands["nir"] - bands["red"]
        ratio = np.where(bands["red"] != 0, bands["nir"] / bands["red"], 0)
        blue = bands["green"] * 0.8
        evi = 2.5 * (bands["nir"] - bands["red"]) / (bands["nir"] + 6*bands["red"] - 7.5*blue + 1)

        # 3x3 convolution
        from scipy.ndimage import uniform_filter
        convolved = uniform_filter(bands["nir"], size=3, mode="reflect")

        return time.perf_counter() - start


# =============================================================================
# Scenario 8: Zonal Statistics Scaling
# =============================================================================

class ZonalStatsScaling(ScalingBenchmark):
    """Zonal statistics scaling.
    
    Scales raster dimensions with fixed 100 rectangular zones.
    Expected: O(n^2) for raster operations.
    """
    N_ZONES = 10

    def __init__(self, quick=False):
        scales = ZONAL_SCALES_QUICK if quick else ZONAL_SCALES
        super().__init__("zonal_stats", scales, n_runs=5, unit="pixels per side (n x n)")

    def setup_at_scale(self, scale_name, n):
        np.random.seed(42)
        raster = (np.random.rand(n, n) * 3000).astype(np.float32)

        # Create zone mask
        mask = np.zeros((n, n), dtype=np.int32)
        lat_step = 180.0 / n
        lon_step = 360.0 / n

        for zone_id in range(1, self.N_ZONES * self.N_ZONES + 1):
            i = (zone_id - 1) // self.N_ZONES
            j = (zone_id - 1) % self.N_ZONES
            min_lon = -180.0 + j * lon_step
            max_lon = min_lon + lon_step
            min_lat = -90.0 + i * lat_step
            max_lat = min_lat + lat_step

            r0 = max(0, int((90 - max_lat) / lat_step))
            r1 = min(n, int((90 - min_lat) / lat_step) + 1)
            c0 = max(0, int((min_lon + 180) / lon_step))
            c1 = min(n, int((max_lon + 180) / lon_step) + 1)
            mask[r0:r1, c0:c1] = zone_id

        unique_zones = np.unique(mask)
        unique_zones = unique_zones[unique_zones > 0]

        return raster, mask, unique_zones

    def run_at_scale(self, setup_result):
        raster, mask, unique_zones = setup_result
        start = time.perf_counter()

        results = []
        for zone_id in unique_zones:
            zone_mask = mask == zone_id
            if zone_mask.sum() == 0:
                continue
            values = raster[zone_mask]
            results.append({
                "zone": int(zone_id),
                "mean": float(values.mean()),
                "std": float(values.std()),
                "sum": float(values.sum()),
                "count": int(len(values)),
            })

        return time.perf_counter() - start


# =============================================================================
# Scenario 9: Coordinate Reprojection Scaling
# =============================================================================

class ReprojectionScaling(ScalingBenchmark):
    """Coordinate reprojection scaling.
    
    Scales number of points. Expected: O(n).
    """

    def __init__(self, quick=False):
        scales = REPROJ_SCALES_QUICK if quick else REPROJ_SCALES
        super().__init__("coordinate_reprojection", scales, n_runs=5, unit="points")

    def setup_at_scale(self, scale_name, n_points):
        from pyproj import Transformer
        np.random.seed(42)
        lats = np.random.uniform(-90, 90, n_points)
        lons = np.random.uniform(-180, 180, n_points)
        transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
        return lats, lons, transformer

    def run_at_scale(self, setup_result):
        lats, lons, transformer = setup_result
        start = time.perf_counter()
        x, y = transformer.transform(lons, lats)
        return time.perf_counter() - start


# =============================================================================
# Main Execution
# =============================================================================

def build_benchmark_suite(quick=False):
    """Build the complete scaling benchmark suite covering all 9 scenarios."""
    return [
        # Scenario 1: Matrix Operations
        MatrixCrossProductScaling(quick=quick),
        MatrixDeterminantScaling(quick=quick),
        MatrixPowerScaling(quick=quick),
        SortingScaling(quick=quick),

        # Scenario 2: I/O Operations
        CSVWriteScaling(quick=quick),
        BinaryWriteScaling(quick=quick),

        # Scenario 3: Hyperspectral SAM
        HyperspectralSAMScaling(quick=quick),

        # Scenario 4: Vector Point-in-Polygon
        VectorPipScaling(quick=quick),

        # Scenario 5: IDW Interpolation
        IDWInterpolationScaling(quick=quick),

        # Scenario 6: Time-Series NDVI
        TimeseriesNDVIVScaling(quick=quick),

        # Scenario 7: Raster Algebra
        RasterAlgebraScaling(quick=quick),

        # Scenario 8: Zonal Statistics
        ZonalStatsScaling(quick=quick),

        # Scenario 9: Coordinate Reprojection
        ReprojectionScaling(quick=quick),
    ]


def generate_summary(all_outputs):
    """Generate a combined summary of all scaling results."""
    summary = {
        "thesis_scaling_summary": True,
        "methodology": "Chen & Revels (2016): minimum time as primary estimator",
        "complexity_results": {},
        "scaling_data": {},
    }

    for output in all_outputs:
        name = output["benchmark"]
        summary["complexity_results"][name] = output.get("complexity_analysis", {})
        summary["scaling_data"][name] = {
            "scales": output["scales"],
            "n_runs": output["n_runs"],
            "unit": output["unit"],
            "min_times": {s: r["min"] for s, r in output["results"].items()},
        }

    return summary


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Data Scaling Benchmark Suite — All 9 Thesis Scenarios",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 benchmark_scaling.py              # Full scaling run
  python3 benchmark_scaling.py --quick       # Smaller scales for testing
  python3 benchmark_scaling.py --runs 20     # More runs per scale
  python3 benchmark_scaling.py --scenario matrix  # Run only matrix benchmarks
        """,
    )
    parser.add_argument("--quick", action="store_true",
                        help="Use smaller scales for faster testing")
    parser.add_argument("--runs", type=int, default=10,
                        help="Number of runs per scale (default: 10)")
    parser.add_argument("--scenario", type=str, default="all",
                        choices=["all", "matrix", "io", "hyperspectral",
                                 "vector", "idw", "timeseries", "raster",
                                 "zonal", "reprojection"],
                        help="Run only a specific scenario group")
    args = parser.parse_args()

    print("=" * 70)
    print("DATA SCALING BENCHMARK SUITE — ALL 9 THESIS SCENARIOS")
    print("=" * 70)
    print(f"Mode: {'Quick' if args.quick else 'Full'}")
    print(f"Runs per scale: {args.runs}")
    print("Methodology: Chen & Revels (2016) — minimum time as primary estimator")

    # Build benchmark suite
    all_benchmarks = build_benchmark_suite(quick=args.quick)

    # Filter by scenario if requested
    scenario_map = {
        "matrix": ["matrix_crossproduct", "matrix_determinant", "matrix_power", "sorting"],
        "io": ["io_csv_write", "io_binary_write"],
        "hyperspectral": ["hyperspectral_sam"],
        "vector": ["vector_pip"],
        "idw": ["interpolation_idw"],
        "timeseries": ["timeseries_ndvi"],
        "raster": ["raster_algebra"],
        "zonal": ["zonal_stats"],
        "reprojection": ["coordinate_reprojection"],
    }

    if args.scenario != "all":
        allowed = set(scenario_map.get(args.scenario, []))
        all_benchmarks = [b for b in all_benchmarks if b.name in allowed]
        print(f"Scenario filter: {args.scenario} ({len(all_benchmarks)} benchmarks)")

    # Set custom run count
    for benchmark in all_benchmarks:
        benchmark.n_runs = args.runs

    # Run all benchmarks
    all_outputs = []
    for benchmark in all_benchmarks:
        try:
            benchmark.run_all_scales()
            output = benchmark.save_results()
            all_outputs.append(output)
        except Exception as e:
            print(f"\n  ERROR in {benchmark.name}: {e}")
            import traceback
            traceback.print_exc()

    # Generate combined summary
    if all_outputs:
        summary = generate_summary(all_outputs)
        output_dir = Path(__file__).parent / "results" / "scaling"
        try:
            output_dir.mkdir(parents=True, exist_ok=True)
            summary_path = output_dir / "combined_scaling_summary.json"
            with open(summary_path, "w") as f:
                json.dump(summary, f, indent=2)
        except PermissionError:
            summary_path = Path("/tmp/thesis_scaling/combined_scaling_summary.json")
            summary_path.parent.mkdir(parents=True, exist_ok=True)
            with open(summary_path, "w") as f:
                json.dump(summary, f, indent=2)
        print(f"\n  Combined summary: {summary_path}")

    # Print final summary table
    print(f"\n{'='*70}")
    print("SCALING ANALYSIS COMPLETE")
    print(f"{'='*70}")
    print(f"\n{'Benchmark':<30} {'Scaling Exponent':>16} {'R²':>6} {'Complexity':<30}")
    print("-" * 82)

    for output in all_outputs:
        name = output["benchmark"]
        ca = output.get("complexity_analysis", {})
        k = ca.get("scaling_exponent", "N/A")
        r2 = ca.get("r_squared", "N/A")
        label = ca.get("complexity_label", "N/A")
        k_str = f"{k:.3f}" if isinstance(k, float) else str(k)
        r2_str = f"{r2:.4f}" if isinstance(r2, float) else str(r2)
        print(f"{name:<30} {k_str:>16} {r2_str:>6} {label:<30}")

    print(f"\n{'='*70}")
    print(f"Generated files:")
    for output in all_outputs:
        print(f"  results/scaling/{output['benchmark']}_scaling.json")
    print(f"  results/scaling/combined_scaling_summary.json")
    print(f"{'='*70}")


if __name__ == "__main__":
    main()
