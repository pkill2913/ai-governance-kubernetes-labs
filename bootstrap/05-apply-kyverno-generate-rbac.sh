#!/usr/bin/env bash
# Apply least-privilege RBAC required by Kyverno Background Controller so the
# Lab 03 GeneratingPolicy can create/synchronize Roles and RoleBindings.
#
# - Namespace Role/RoleBinding in ai-agent-lab (manage roles/rolebindings)
# - ClusterRole/ClusterRoleBinding list+watch (sync watcher is cluster-scoped)
#
# Does NOT grant cluster-admin.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl create namespace ai-agent-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${ROOT_DIR}/lab03-ai-agent/kyverno-watch-rbac.yaml"
kubectl apply -f "${ROOT_DIR}/lab03-ai-agent/kyverno-generate-permissions.yaml"

echo "Kyverno Background Controller RBAC for Lab 03 applied."
echo "Note: Synchronize restores drifted generated resources after detection;"
echo "it does not eliminate temporary privilege-exposure windows."
