#!/usr/bin/env bash
# Add the GPU pool back and wait for the model pod to be Ready. Measured on
# de-fra-2: ~1.5 min for the apply, ~4 min for the node, ~13 min for the image
# and weights.
#
# Usage: scripts/gpu-up.sh [timeout, default 30m]
set -euo pipefail

timeout="${1:-30m}"

cd "$(dirname "${BASH_SOURCE[0]}")/../tofu"
vars_file=tofu.auto.tfvars
if [[ -f "$vars_file" ]] && grep -qE '^[[:space:]]*gpu_enabled[[:space:]]*=' "$vars_file"; then
  sed -i -E 's/^([[:space:]]*gpu_enabled[[:space:]]*=[[:space:]]*)[^#\/]*([[:space:]]+(#.*|\/\/.*))?$/\1true\2/' "$vars_file"
else
  printf '\ngpu_enabled = true\n' >> "$vars_file"
fi
# Targeted: only the pool changes, and this skips fetching every Helm chart.
tofu apply -auto-approve \
  -target=linode_lke_cluster.gpu_cluster \
  -target=linode_firewall.lke_firewall

kubectl_context="$(tofu output -raw kubectl_context)"
# Not the LLMInferenceService: its Ready condition stays True while the pod is Pending.
set +e
timeout "$timeout" bash -c "
  set -euo pipefail
  while true; do
    pods=\$(kubectl --context \"\$1\" get pods -n vllm -o name)
    [[ -n \"\$pods\" ]] && exit 0
    sleep 5
  done
" _ "$kubectl_context"
status=$?
set -e
if (( status != 0 )); then
  if (( status == 124 )); then
    echo "Timed out waiting for a model pod in namespace vllm." >&2
  else
    echo "Failed to discover model pods in namespace vllm." >&2
  fi
  exit "$status"
fi
kubectl --context "$kubectl_context" wait pod --all -n vllm --for=condition=Ready --timeout="$timeout"
