#!/usr/bin/env bash
# Restarts the HAMi scheduler Deployment and waits for the rollout. HAMi only
# reads hami-scheduler-device at process startup, so the ConfigMap patch has no
# effect until the scheduler restarts.
#
# Usage: restart-scheduler.sh <kubeconfig-path> <namespace> <deployment>
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <kubeconfig-path> <namespace> <deployment>" >&2
  exit 2
fi

kubeconfig="$1"
namespace="$2"
deployment="$3"

kubectl --kubeconfig "${kubeconfig}" \
  rollout restart "deployment/${deployment}" -n "${namespace}"
kubectl --kubeconfig "${kubeconfig}" \
  rollout status "deployment/${deployment}" -n "${namespace}" --timeout=120s
