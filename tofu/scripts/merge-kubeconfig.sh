#!/usr/bin/env sh
# Merges a base64-encoded LKE kubeconfig into ~/.kube/config and activates
# the cluster context. Called by tofu/kubeconfig.tf via local-exec.
#
# Environment variables (set by OpenTofu):
#   LKE_KUBECONFIG_B64  - base64-encoded kubeconfig content
#   LKE_CLUSTER_ID      - LKE cluster ID (for context name)

set -eu

# Preflight: kubectl must be available on PATH for kubeconfig merge to work.
# If it is absent, print an actionable error and exit cleanly so the operator
# knows exactly what to do rather than seeing an opaque 'not found' failure.
if ! command -v kubectl > /dev/null 2>&1; then
  echo "Error: 'kubectl' not found on PATH." >&2
  echo "  Install kubectl (https://kubernetes.io/docs/tasks/tools/) and re-run" >&2
  echo "  'tofu apply', or set merge_kubeconfig = false in tofu.tfvars to skip" >&2
  echo "  the automatic kubeconfig merge and manage it externally." >&2
  exit 1
fi

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

# Activate the new context (explicitly target only ~/.kube/config to avoid
# permission errors from other entries in a multi-path KUBECONFIG).
KUBECONFIG=~/.kube/config kubectl config use-context "lke${LKE_CLUSTER_ID}-ctx"

# Cleanup
rm -f "${TEMP_KUBECONFIG}"

echo "Kubeconfig merged into ~/.kube/config"
echo "Context 'lke${LKE_CLUSTER_ID}-ctx' is now active"
