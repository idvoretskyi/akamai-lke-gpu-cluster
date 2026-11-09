#!/usr/bin/env bash
# Add the GPU pool back and wait for the model pod to be Ready. Measured on
# de-fra-2: ~1.5 min for the apply, ~4 min for the node, ~4 min for the vLLM
# image, ~1 min for the weights from Object Storage, ~2 min for vLLM to start.
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
k() { kubectl --context "$kubectl_context" "$@"; }

# Poll a command until it succeeds or the deadline passes.
case "$timeout" in
  *h) seconds=$(( ${timeout%h} * 3600 )) ;;
  *m) seconds=$(( ${timeout%m} * 60 )) ;;
  *s) seconds=${timeout%s} ;;
  *) seconds=$timeout ;;
esac
deadline=$(( $(date +%s) + seconds ))
wait_for() {
  local what="$1"; shift
  until "$@" >/dev/null 2>&1; do
    if (( $(date +%s) >= deadline )); then
      echo "Timed out waiting for $what." >&2
      exit 1
    fi
    sleep 5
  done
}

has_pods() { [[ -n "$(k get pods -n vllm -o name)" ]]; }
gpu_advertised() {
  k get nodes -l nodepool.lke/role=gpu \
    -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' | grep -q '[1-9]'
}

# Not the LLMInferenceService: its Ready condition stays True while the pod is Pending.
wait_for "a model pod in namespace vllm" has_pods

# HAMi's scheduler rejects the model pod until the GPU node's device plugin has
# registered the GPU, and the scheduler then leaves the pod in backoff for ~5
# min. Once the GPU is advertised, recreate the pod to schedule it right away.
wait_for "the GPU to be advertised" gpu_advertised
sleep 15
# Only unscheduled pods: one already on a node is pulling the image or weights.
k delete pod -n vllm --field-selector=status.phase=Pending,spec.nodeName= --wait=true --timeout=120s
wait_for "the replacement model pod" has_pods

k wait pod --all -n vllm --for=condition=Ready --timeout="$timeout"
