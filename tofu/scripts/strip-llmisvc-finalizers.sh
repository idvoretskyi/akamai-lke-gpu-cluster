#!/usr/bin/env bash
# Destroy-time helper (run by terraform_data.llmisvc_config_guard in
# platform.tf): by the time the presets chart is uninstalled the LLMInferenceService
# controller is gone, so nobody removes the finalizer it put on each
# LLMInferenceServiceConfig and the uninstall would hang. Strip them.
# Best effort: never fails the destroy (the cluster may already be unreachable).
#
# Environment (set by OpenTofu):
#   LKE_KUBECONFIG_B64  base64-encoded kubeconfig
set -uo pipefail

[ -n "${LKE_KUBECONFIG_B64:-}" ] && command -v kubectl >/dev/null 2>&1 || exit 0

cfg=$(mktemp)
trap 'rm -f "$cfg"' EXIT
chmod 600 "$cfg"
echo "$LKE_KUBECONFIG_B64" | base64 -d >"$cfg"

for name in $(kubectl --kubeconfig "$cfg" get llminferenceserviceconfigs.serving.kserve.io -n kserve -o name 2>/dev/null); do
  kubectl --kubeconfig "$cfg" patch "$name" -n kserve --type merge \
    -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
done
exit 0
