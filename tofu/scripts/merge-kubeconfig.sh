#!/usr/bin/env bash
# Merges a base64-encoded LKE kubeconfig into ~/.kube/config and activates the
# cluster's context. Run by tofu/kubeconfig.tf via local-exec.
#
# Environment (set by OpenTofu):
#   LKE_KUBECONFIG_B64  base64-encoded kubeconfig
#   LKE_CLUSTER_ID      LKE cluster ID (names the context: lke<ID>-ctx)
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Error: 'kubectl' not found on PATH." >&2
  echo "  Install kubectl (https://kubernetes.io/docs/tasks/tools/) and re-run" >&2
  echo "  'tofu apply', or set merge_kubeconfig = false in tofu.auto.tfvars to skip" >&2
  echo "  the automatic kubeconfig merge and manage it externally." >&2
  exit 1
fi

if [ -z "${LKE_KUBECONFIG_B64:-}" ] || [ -z "${LKE_CLUSTER_ID:-}" ]; then
  echo "Error: LKE_KUBECONFIG_B64 and LKE_CLUSTER_ID must be set." >&2
  exit 1
fi

mkdir -p ~/.kube

# One backup of the existing config, overwritten on each run.
if [ -f ~/.kube/config ]; then
  cp ~/.kube/config ~/.kube/config.backup
fi

# Temp files hold credentials: create them private and remove them on any exit.
# The merged file is created inside ~/.kube so the final mv is a rename on the
# same filesystem, which is atomic: ~/.kube/config is either the old file or the
# complete new one, never half-written (a plain cp would truncate it first).
new=$(mktemp)
merged=$(mktemp ~/.kube/config.XXXXXX)
trap 'rm -f "$new" "$merged"' EXIT
chmod 600 "$new" "$merged"

printf '%s' "$LKE_KUBECONFIG_B64" | base64 -d >"$new"

KUBECONFIG=~/.kube/config:"$new" kubectl config view --flatten >"$merged"
mv "$merged" ~/.kube/config

# Activate the new context; target only ~/.kube/config so other entries in a
# multi-path KUBECONFIG cannot cause permission errors.
KUBECONFIG=~/.kube/config kubectl config use-context "lke${LKE_CLUSTER_ID}-ctx"

echo "Kubeconfig merged into ~/.kube/config"
echo "Context 'lke${LKE_CLUSTER_ID}-ctx' is now active"
