#!/usr/bin/env bash
# Add the GPU pool back and wait for the model pod to be Ready. Measured on
# de-fra-2: ~1.5 min for the apply, ~4 min for the node, ~13 min for the image
# and weights.
#
# Usage: scripts/gpu-up.sh [timeout, default 30m]
set -euo pipefail

timeout="${1:-30m}"

cd "$(dirname "${BASH_SOURCE[0]}")/../tofu"
# Targeted: only the pool changes, and this skips fetching every Helm chart.
tofu apply -auto-approve -var gpu_enabled=true -target=linode_lke_cluster.gpu_cluster

# Not the LLMInferenceService: its Ready condition stays True while the pod is Pending.
until kubectl get pods -n vllm -o name 2>/dev/null | grep -q .; do sleep 5; done
kubectl wait pod --all -n vllm --for=condition=Ready --timeout="$timeout"
