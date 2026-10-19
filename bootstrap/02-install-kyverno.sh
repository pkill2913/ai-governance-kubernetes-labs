#!/usr/bin/env bash
# Install Kyverno chart 3.9.1 (app v1.19.1), matching the tested workshop cluster.
# Idempotent: upgrades if the release already exists.
set -euo pipefail

NAMESPACE="${KYVERNO_NAMESPACE:-kyverno}"
RELEASE="${KYVERNO_RELEASE:-kyverno}"
CHART_VERSION="${KYVERNO_CHART_VERSION:-3.9.1}"

helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update kyverno >/dev/null

if helm status "${RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Upgrading existing Kyverno release ${RELEASE} (chart ${CHART_VERSION})..."
  helm upgrade "${RELEASE}" kyverno/kyverno \
    --namespace "${NAMESPACE}" \
    --version "${CHART_VERSION}" \
    --wait
else
  echo "Installing Kyverno release ${RELEASE} (chart ${CHART_VERSION})..."
  helm install "${RELEASE}" kyverno/kyverno \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --version "${CHART_VERSION}" \
    --wait
fi

kubectl -n "${NAMESPACE}" get pods
echo "Kyverno ready (expected app version v1.19.1)."
