#!/usr/bin/env bash
# Create lab namespaces and platform labels used by Lab 04 mutation.
# Idempotent.
set -euo pipefail

for ns in ai-dev ai-ml ai-prod ai-supply ai-agent-lab ai-traceability; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace ai-traceability \
  ai.company.io/team=ml-platform \
  ai.company.io/cost-center=CC-1024 \
  --overwrite

kubectl get ns ai-dev ai-ml ai-prod ai-supply ai-agent-lab ai-traceability \
  --show-labels
echo "Lab namespaces ready."
