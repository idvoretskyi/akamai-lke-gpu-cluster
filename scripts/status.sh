#!/usr/bin/env bash
# Is the stack healthy? Prints nodes, the model, the Argo CD application and
# any pod that is not Running/Completed. Exits non-zero if something is wrong.
#
# Usage: scripts/status.sh
set -euo pipefail

ctx=$(kubectl config current-context)
echo "context: $ctx"
echo

echo "== nodes"
kubectl get nodes

echo
echo "== model (InferenceService)"
kubectl get inferenceservice -A

echo
echo "== Argo CD applications"
kubectl get applications -n argocd

echo
echo "== gateway"
kubectl get gateway -n kserve

echo
echo "== pods that are not healthy"
bad=$(kubectl get pods -A --no-headers | grep -v -E '[[:space:]](Running|Completed)[[:space:]]' || true)
if [ -n "$bad" ]; then
  echo "$bad"
  exit 1
fi
echo "none, all pods are Running or Completed"
