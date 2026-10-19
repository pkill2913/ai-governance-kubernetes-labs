#!/usr/bin/env bash
# Install NVIDIA Mokka (nvml-mock) and the mock device plugin from this repo.
# Simulated GPUs only — no physical NVIDIA hardware required.
# Values match the tested workshop cluster: gpu.count=8, gpu.profile=h100.
# Prerequisite: Kind cluster (script 01). Does not delete the cluster.
# Note: deploys a privileged device-plugin DaemonSet (expected for Mokka).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${MOKKA_NAMESPACE:-mokka}"
RELEASE="${MOKKA_RELEASE:-nvml-mock}"
# Pin matches the tested workshop release (chart + appVersion 0.5.0-dev).
# Override with MOKKA_CHART_VERSION only if you intentionally diverge.
CHART_VERSION="${MOKKA_CHART_VERSION:-0.5.0-dev}"
GPU_COUNT="${MOKKA_GPU_COUNT:-8}"
GPU_PROFILE="${MOKKA_GPU_PROFILE:-h100}"
DEVICE_PLUGIN_MANIFEST="${ROOT_DIR}/lab01-gpu/nvidia-device-plugin.yaml"
CHART="oci://ghcr.io/nvidia/k8s-test-infra/chart/nvml-mock"

common_args=(
  --namespace "${NAMESPACE}"
  --set "gpu.count=${GPU_COUNT}"
  --set "gpu.profile=${GPU_PROFILE}"
  --wait
  --timeout 120s
)

if [[ -n "${CHART_VERSION}" ]]; then
  common_args+=(--version "${CHART_VERSION}")
fi

if helm status "${RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Upgrading existing Mokka release ${RELEASE}..."
  helm upgrade "${RELEASE}" "${CHART}" "${common_args[@]}"
else
  echo "Installing Mokka release ${RELEASE}..."
  helm install "${RELEASE}" "${CHART}" \
    --create-namespace \
    "${common_args[@]}"
fi

kubectl label node --all mokka.nvidia.com/type=sgpu --overwrite
kubectl apply -f "${DEVICE_PLUGIN_MANIFEST}"
kubectl -n kube-system wait --for=condition=ready \
  pod -l name=nvidia-device-plugin-mock --timeout=120s

kubectl get nodes -o custom-columns=\
'NODE:.metadata.name,GPUS:.status.allocatable.nvidia\.com/gpu'

echo "Mokka + mock device plugin ready (simulated GPUs)."
