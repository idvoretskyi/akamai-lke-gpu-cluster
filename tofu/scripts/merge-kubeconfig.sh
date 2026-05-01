#!/usr/bin/env sh
# Merges a base64-encoded LKE kubeconfig into ~/.kube/config and activates
# the cluster context. Called by tofu/kubeconfig.tf via local-exec.
#
# Environment variables (set by OpenTofu):
#   LKE_KUBECONFIG_B64  - base64-encoded kubeconfig content
#   LKE_CLUSTER_ID      - LKE cluster ID (for context name)

set -eu

if [ -z "${LKE_KUBECONFIG_B64:-}" ] || [ -z "${LKE_CLUSTER_ID:-}" ]; then
  echo "Error: LKE_KUBECONFIG_B64 and LKE_CLUSTER_ID must be set." >&2
  exit 1
fi

# Ensure ~/.kube exists
mkdir -p ~/.kube

# Backup existing config if present
if [ -f ~/.kube/config ]; then
  cp ~/.kube/config ~/.kube/config.backup."$(date +%Y%m%d-%H%M%S)"
fi

# Decode kubeconfig to a temp file
TEMP_KUBECONFIG=$(mktemp)
printf '%s' "${LKE_KUBECONFIG_B64}" | base64 -d > "${TEMP_KUBECONFIG}"
chmod 600 "${TEMP_KUBECONFIG}"

# Merge into ~/.kube/config
KUBECONFIG=~/.kube/config:"${TEMP_KUBECONFIG}" kubectl config view --flatten > ~/.kube/config.tmp
mv ~/.kube/config.tmp ~/.kube/config
chmod 600 ~/.kube/config

# Activate the new context
kubectl config use-context "lke${LKE_CLUSTER_ID}-ctx"

# Cleanup
rm -f "${TEMP_KUBECONFIG}"

echo "Kubeconfig merged into ~/.kube/config"
echo "Context 'lke${LKE_CLUSTER_ID}-ctx' is now active"
