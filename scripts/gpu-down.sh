#!/usr/bin/env bash
# Remove the GPU pool to stop paying for the GPU (~$0.52/hr). The cluster and
# platform stay up; the model stays Pending until scripts/gpu-up.sh.
#
# Usage: scripts/gpu-down.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../tofu"
vars_file=tofu.auto.tfvars
if [[ -f "$vars_file" ]] && grep -qE '^[[:space:]]*gpu_enabled[[:space:]]*=' "$vars_file"; then
  sed -i -E 's/^([[:space:]]*gpu_enabled[[:space:]]*=[[:space:]]*)[^#\/]*([[:space:]]+(#.*|\/\/.*))?$/\1false\2/' "$vars_file"
else
  printf '\ngpu_enabled = false\n' >> "$vars_file"
fi
# Targeted: only the pool changes, and this skips fetching every Helm chart.
tofu apply -auto-approve -target=linode_lke_cluster.gpu_cluster
