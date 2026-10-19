#!/usr/bin/env bash
# Create the Kind cluster named devopsdays (Podman on macOS/Apple Silicon).
# Idempotent: exits successfully if the cluster already exists.
# Does NOT delete or recreate an existing cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-devopsdays}"
KIND_CONFIG="${KIND_CONFIG:-${ROOT_DIR}/bootstrap/kind-config.yaml}"

export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists; leaving it unchanged."
  kubectl cluster-info --context "kind-${CLUSTER_NAME}"
  exit 0
fi

echo "Creating Kind cluster '${CLUSTER_NAME}' with provider=${KIND_EXPERIMENTAL_PROVIDER}"
kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo "Cluster ready."
