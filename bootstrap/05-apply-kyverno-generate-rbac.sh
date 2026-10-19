#!/usr/bin/env bash
# Apply least-privilege RBAC required by Kyverno Background Controller so the
# Lab 03 GeneratingPolicy can create/synchronize Roles and RoleBindings.
#
# - Namespace Role/RoleBinding in ai-agent-lab:
#     get/list/watch/create/update/patch/delete on roles + rolebindings
#     (Generate needs create; Synchronize needs read/update/delete/recreate)
# - ClusterRole/ClusterRoleBinding list+watch on roles + rolebindings
#     (Kyverno v1.19 synchronize watcher is cluster-scoped)
#
# Prerequisite: Kyverno installed (script 02) so ServiceAccount
# kyverno-background-controller exists in namespace kyverno.
# Does NOT grant cluster-admin. Does not delete the Kind cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_RBAC="${ROOT_DIR}/lab03-ai-agent/kyverno-watch-rbac.yaml"
GENERATE_RBAC="${ROOT_DIR}/lab03-ai-agent/kyverno-generate-permissions.yaml"

if [[ ! -f "${WATCH_RBAC}" || ! -f "${GENERATE_RBAC}" ]]; then
  echo "ERROR: expected Lab 03 Kyverno RBAC manifests are missing." >&2
  exit 1
fi

if ! kubectl -n kyverno get sa kyverno-background-controller >/dev/null 2>&1; then
  echo "ERROR: ServiceAccount kyverno/kyverno-background-controller not found." >&2
  echo "Run ./bootstrap/02-install-kyverno.sh first." >&2
  exit 1
fi

kubectl create namespace ai-agent-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${WATCH_RBAC}"
kubectl apply -f "${GENERATE_RBAC}"

echo "Kyverno Background Controller RBAC for Lab 03 applied."
echo "Note: Synchronize restores drifted generated resources after detection;"
echo "it does not eliminate temporary privilege-exposure windows."
