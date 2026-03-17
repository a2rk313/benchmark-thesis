#!/usr/bin/env bash
# Pull pre-built containers from GitHub Container Registry
# Run this instead of building locally

set -euo pipefail

REGISTRY="ghcr.io"
OWNER="${OWNER:-$(gh repo view --json owner -q .owner.login)}"

echo "Pulling containers from $REGISTRY/$OWNER..."

podman pull "$REGISTRY/$OWNER/thesis-python:3.14" || podman pull "$REGISTRY/$OWNER/thesis-python:latest"
podman pull "$REGISTRY/$OWNER/thesis-julia:1.11" || podman pull "$REGISTRY/$OWNER/thesis-julia:latest"
podman pull "$REGISTRY/$OWNER/thesis-r:4.5" || podman pull "$REGISTRY/$OWNER/thesis-r:latest"

# Tag for local use (matches run_benchmarks.sh expectations)
podman tag "$REGISTRY/$OWNER/thesis-python:latest" "thesis-python:3.13"
podman tag "$REGISTRY/$OWNER/thesis-julia:latest" "thesis-julia:1.11"
podman tag "$REGISTRY/$OWNER/thesis-r:latest" "thesis-r:4.5"

echo "✓ Containers ready"
podman images | grep thesis
