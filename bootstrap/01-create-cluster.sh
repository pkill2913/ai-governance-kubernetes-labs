#!/usr/bin/env bash
# Create the Kind cluster named devopsdays (Podman on macOS/Apple Silicon).
# Idempotent: exits successfully if the cluster already exists.
# Does NOT delete or recreate an existing cluster.
#
# Expected tooling for the pinned node image in kind-config.yaml:
#   Kind v0.33.x + kindest/node:v1.37.0@sha256:a1ed56cf...
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-devopsdays}"
KIND_CONFIG="${KIND_CONFIG:-${ROOT_DIR}/bootstrap/kind-config.yaml}"

export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

if ! command -v kind >/dev/null 2>&1; then
  echo "ERROR: kind not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${KIND_CONFIG}" ]]; then
  echo "ERROR: Kind config not found: ${KIND_CONFIG}" >&2
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists; leaving it unchanged."
  kubectl cluster-info --context "kind-${CLUSTER_NAME}"
  exit 0
fi

echo "Creating Kind cluster '${CLUSTER_NAME}' with provider=${KIND_EXPERIMENTAL_PROVIDER}"
echo "Config: ${KIND_CONFIG}"
kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo "Cluster ready."
