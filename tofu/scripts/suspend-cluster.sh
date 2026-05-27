#!/usr/bin/env bash
# suspend-cluster.sh — Scale the LKE GPU node pool down to 0 nodes to pause
# compute spend without destroying the cluster, persistent volumes, or the
# control plane. Uses `linode-cli`; requires LINODE_TOKEN or a configured CLI.
#
# Note: LKE autoscaler does NOT support min=0 (Linode requires min>=1). This
# script bypasses the autoscaler by directly updating pool count via the API.
# Subsequent `tofu apply` will re-introduce drift unless you also temporarily
# set gpu_node_count = 0 (and a matching autoscaler_min) in your tfvars, OR
# accept the drift and run `tofu apply -refresh-only` before resuming.
#
# Usage:
#   ./suspend-cluster.sh <cluster_id> [pool_id]
#
# If pool_id is omitted, the first pool of the cluster is used.

set -euo pipefail

CLUSTER_ID="${1:?cluster_id required (run: tofu output -raw cluster_id)}"
POOL_ID="${2:-}"

if ! command -v linode-cli >/dev/null 2>&1; then
  echo "linode-cli not found. Install via: pip3 install linode-cli" >&2
  exit 1
fi

if [[ -z "${POOL_ID}" ]]; then
  POOL_ID="$(linode-cli lke pools-list "${CLUSTER_ID}" --json | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["id"])')"
fi

echo "Suspending cluster ${CLUSTER_ID}, pool ${POOL_ID}: setting node count to 0…"
linode-cli lke pool-update "${CLUSTER_ID}" "${POOL_ID}" --count 0
echo "Done. Resume with: $(dirname "$0")/resume-cluster.sh ${CLUSTER_ID} ${POOL_ID} <node_count>"
