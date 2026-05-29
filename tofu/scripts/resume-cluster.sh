#!/usr/bin/env bash
# resume-cluster.sh — Restore the LKE GPU node pool to the requested node count
# after a prior `suspend-cluster.sh`. See that script for caveats around
# `tofu apply` drift.
#
# Usage:
#   ./resume-cluster.sh <cluster_id> [pool_id] [node_count=1]
#
# If pool_id is omitted, the GPU pool (instance type prefixed "g2-gpu") is used,
# falling back to the first pool.

set -euo pipefail

CLUSTER_ID="${1:?cluster_id required (run: tofu output -raw cluster_id)}"
POOL_ID="${2:-}"
NODE_COUNT="${3:-1}"

if ! command -v linode-cli >/dev/null 2>&1; then
  echo "linode-cli not found. Install via: pip3 install linode-cli" >&2
  exit 1
fi

if [[ -z "${POOL_ID}" ]]; then
  POOL_ID="$(linode-cli lke pools-list "${CLUSTER_ID}" --json | python3 -c 'import json,sys; pools = json.load(sys.stdin); gpu = [p for p in pools if p.get("type", "").startswith("g2-gpu")]; print((gpu or pools)[0]["id"])')"
fi

echo "Resuming cluster ${CLUSTER_ID}, pool ${POOL_ID}: setting node count to ${NODE_COUNT}…"
linode-cli lke pool-update "${CLUSTER_ID}" "${POOL_ID}" --count "${NODE_COUNT}"
echo "Done. Verify with: kubectl get nodes"
