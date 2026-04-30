# Documentation Index — Thesis Benchmarking Framework

This directory contains detailed documentation for the benchmark-thesis project. Below is a guide to all available documentation files and their purpose.

---

## Core Documentation

| File | Purpose | Audience |
|------|---------|----------|
| [../README.md](../README.md) | **Main project documentation** — overview, quick start, benchmark descriptions | Everyone |
| [../THESIS_METHODOLOGY.md](../THESIS_METHODOLOGY.md) | **Thesis Chapter 3: Research Methodology** — experimental design, statistical protocol | Thesis committee, reviewers |
| [METHODOLOGY_CHEN_REVELS.md](METHODOLOGY_CHEN_REVELS.md) | Detailed implementation of Chen & Revels (2016) benchmarking methodology | Researchers, statisticians |
| [BENCHMARK_FAIRNESS.md](BENCHMARK_FAIRNESS.md) | Analysis of fairness across language implementations | Reviewers, thesis committee |

## Getting Started

| File | Purpose |
|------|---------|
| [QUICK_START.md](QUICK_START.md) | Quick setup guide for new users |
| [QUICK_START_MISE.md](QUICK_START_MISE.md) | Setup guide using mise (version manager) |
| [NATIVE_QUICK_START.md](NATIVE_QUICK_START.md) | Running benchmarks natively (without containers) |
| [NATIVE_BARE_METAL_GUIDE.md](NATIVE_BARE_METAL_GUIDE.md) | Complete guide to bare-metal benchmarking |

## Architecture and Design

| File | Purpose |
|------|---------|
| [CONTAINER_OPTIMIZATION.md](CONTAINER_OPTIMIZATION.md) | Container build optimization strategies |
| [CONTAINER_OPTIMIZATION_GUIDE.md](CONTAINER_OPTIMIZATION_GUIDE.md) | Guide to optimized container images |
| [CONTAINER_OPTIMIZATION_QUICK.md](CONTAINER_OPTIMIZATION_QUICK.md) | Quick reference for container optimization |
| [CROSS_PLATFORM_NATIVE_GUIDE.md](CROSS_PLATFORM_NATIVE_GUIDE.md) | Running benchmarks across different platforms |
| [CACHING_GUIDE.md](CACHING_GUIDE.md) | Julia package caching strategies |
| [SELECTIVE_CACHE_CONTROL.md](SELECTIVE_CACHE_CONTROL.md) | Fine-grained cache control |

## Data and Datasets

| File | Purpose |
|------|---------|
| [DATA_PROVENANCE.md](DATA_PROVENANCE.md) | Dataset sources, licenses, and processing |
| [CUPRITE_VS_JASPER_RIDGE.md](CUPRITE_VS_JASPER_RIDGE.md) | Comparison of hyperspectral datasets |

## Statistical Analysis

| File | Purpose |
|------|---------|
| [STATISTICAL_FEATURES.md](STATISTICAL_FEATURES.md) | Statistical analysis features and tools |
| [detect_flaky.md](detect_flaky.md) | Flaky benchmark detection methodology |
| [OUTLIER_HANDLING.md](OUTLIER_HANDLING.md) | Outlier detection and handling |
| [regression_testing.md](REGRESSION_TESTING.md) | Regression testing methodology |
| [trend_analysis.md](TREND_ANALYSIS.md) | Performance trend analysis |
| [benchmark_diffing.md](BENCHMARK_DIFFING.md) | Comparing benchmark results over time |

## Version History

| File | Purpose |
|------|---------|
| [CHANGELOG.md](CHANGELOG.md) | Change log |
| [CHANGELOG_v4.0.md](CHANGELOG_V4.0.md) | Version 4.0 changes |
| [VERSION_4_CHANGES.md](VERSION_4_CHANGES.md) | Detailed v4 changes |
| [WHATS_NEW_v4.md](WHATS_NEW_V4.md) | What's new in v4 |
| [UPGRADE_TO_V4.md](UPGRADE_TO_V4.md) | Upgrade guide to v4 |

## Troubleshooting and Maintenance

| File | Purpose |
|------|---------|
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions |
| [GITHUB_CODESPACES.md](GITHUB_CODESPACES.md) | Using GitHub Codespaces |
| [GITHUB_CODESPACES_GUIDE.md](GITHUB_CODESPACES_GUIDE.md) | Detailed Codespaces guide |
| [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) | Implementation checklist |

## Legacy Documentation

These files contain historical information and are superseded by the core documentation:

| File | Status |
|------|--------|
| [README_OLD.md](README_OLD.md) | Superseded by ../README.md |
| [README_v4.md](README_V4.md) | Superseded by ../README.md |
| [README_COMPLETE_v4.md](README_COMPLETE_V4.md) | Superseded by ../README.md |
| [README_ENHANCEMENTS.md](README_ENHANCEMENTS.md) | Superseded by ../README.md |
| [START_HERE.md](START_HERE.md) | Superseded by QUICK_START.md |
| [START_HERE_v4.md](START_HERE_V4.md) | Superseded by QUICK_START.md |
| [MISE_CUPRITE_GUIDE.md](MISE_CUPRITE_GUIDE.md) | Superseded by DATA_PROVENANCE.md |
| [METHODOLOGY_NOTES_FOR_THESIS.md](METHODOLOGY_NOTES_FOR_THESIS.md) | Superseded by ../THESIS_METHODOLOGY.md |
| [PROGRESS_ASSESSMENT.md](PROGRESS_ASSESSMENT.md) | Superseded by ../README.md |
| [IMPROVEMENTS.md](IMPROVEMENTS.md) | Historical |
| [IMPROVEMENTS_SUMMARY.md](IMPROVEMENTS_SUMMARY.md) | Historical |
| [ENHANCEMENTS_INDEX.md](ENHANCEMENTS_INDEX.md) | Historical |

---

## Recommended Reading Order

For new contributors or thesis reviewers:

1. **[../README.md](../README.md)** — Start here for project overview
2. **[../THESIS_METHODOLOGY.md](../THESIS_METHODOLOGY.md)** — Understand the methodology
3. **[BENCHMARK_FAIRNESS.md](BENCHMARK_FAIRNESS.md)** — Understand fairness considerations
4. **[METHODOLOGY_CHEN_REVELS.md](METHODOLOGY_CHEN_REVELS.md)** — Deep dive into statistical methodology
5. **[DATA_PROVENANCE.md](DATA_PROVENANCE.md)** — Understand the datasets
