#!/usr/bin/env python3
"""
Chen & Revels (2016) methodology validation.
Generates stability and distribution plots.
"""

import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
from scipy.stats import gaussian_kde
from scipy.signal import find_peaks
import json
import glob

def analyze_estimator_stability():
    results_files = glob.glob('results/warm_start/*.json')
    for result_file in results_files:
        with open(result_file) as f:
            data = json.load(f)
        times = np.array([r['mean'] for r in data['results']])
        n_trials = 100
        sample_size = 10
        mins, means, medians = [], [], []
        for _ in range(n_trials):
            sample = np.random.choice(times, size=sample_size, replace=True)
            mins.append(np.min(sample))
            means.append(np.mean(sample))
            medians.append(np.median(sample))
        cv_min = np.std(mins) / np.mean(mins)
        cv_mean = np.std(means) / np.mean(means)
        cv_median = np.std(medians) / np.mean(medians)
        fig, ax = plt.subplots(figsize=(10,6))
        ax.plot(range(n_trials), means, 'o', alpha=0.5, label=f'Mean (CV={cv_mean:.4f})', color='green')
        ax.plot(range(n_trials), medians, 'x', alpha=0.5, label=f'Median (CV={cv_median:.4f})', color='black')
        ax.plot(range(n_trials), mins, '^', alpha=0.5, label=f'Minimum (CV={cv_min:.4f})', color='blue')
        ax.set_xlabel('Trial Index')
        ax.set_ylabel('Time (s)')
        ax.set_title(f'Estimator Stability: {result_file}')
        ax.legend()
        ax.grid(True, alpha=0.3)
        plt.tight_layout()
        output_name = result_file.replace('.json', '_stability.png')
        plt.savefig(output_name, dpi=300)
        plt.close()
        print(f"✓ {result_file} – Min CV: {cv_min:.6f}")

def test_normality():
    results_files = glob.glob('results/warm_start/*.json')
    print("\n" + "="*70)
    print("NORMALITY TESTS")
    print("="*70)
    for result_file in results_files:
        with open(result_file) as f:
            data = json.load(f)
        times = np.array([r['mean'] for r in data['results']])
        stat, p_value = stats.shapiro(times)
        print(f"\n{result_file}: W={stat:.4f}, p={p_value:.4f}")
        if p_value < 0.05:
            print(f"  ✓ NOT normally distributed")

def check_multimodality():
    results_files = glob.glob('results/warm_start/*.json')
    print("\n" + "="*70)
    print("MULTIMODALITY ANALYSIS")
    print("="*70)
    for result_file in results_files:
        with open(result_file) as f:
            data = json.load(f)
        times = np.array([r['mean'] for r in data['results']])
        kde = gaussian_kde(times)
        x_range = np.linspace(times.min(), times.max(), 1000)
        density = kde(x_range)
        peaks, _ = find_peaks(density, prominence=0.01)
        plt.figure(figsize=(10,6))
        plt.plot(x_range, density, 'b-', linewidth=2)
        plt.plot(x_range[peaks], density[peaks], 'r^', markersize=10,
                 label=f'{len(peaks)} mode(s)')
        plt.hist(times, bins=30, density=True, alpha=0.3, color='gray')
        plt.xlabel('Time (s)')
        plt.ylabel('Density')
        plt.title(f'Distribution Shape: {result_file}')
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        output_name = result_file.replace('.json', '_distribution.png')
        plt.savefig(output_name, dpi=300)
        plt.close()
        print(f"\n{result_file}: {len(peaks)} mode(s)")

if __name__ == "__main__":
    print("="*70)
    print("CHEN & REVELS (2016) VALIDATION")
    print("="*70)
    analyze_estimator_stability()
    test_normality()
    check_multimodality()
    print("\n✓ Validation complete. Figures saved.")
