#!/usr/bin/env bash
# Is the stack healthy? Prints a PASS/FAIL line per check and exits non-zero if
# any check fails, so it is safe to use in a script or a pipeline.
#
# Checks: every node Ready; every pod Running/Completed and fully Ready; the
# model (InferenceService) Ready; the Argo CD application Synced and Healthy;
# the Gateway Programmed.
#
# Usage: scripts/status.sh
set -euo pipefail

echo "context: $(kubectl config current-context)"
echo

fail=0
check() { # check <name> <ok:0|1> [detail]
  if [ "$2" -eq 0 ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1${3:+: $3}"
    fail=1
  fi
}

# kubectl failing (no cluster, bad credentials) is a failed check, not a crash.
get() { kubectl get "$@" -o json 2>/dev/null; }

# nodes: all Ready
bad=$(get nodes | jq -r '.items[] | select(([.status.conditions[] | select(.type=="Ready")][0].status) != "True") | .metadata.name' || echo "unreachable")
nodes=$(get nodes | jq -r '.items | length' || echo 0)
check "nodes Ready ($nodes)" "$([ -z "$bad" ] && [ "$nodes" -gt 0 ] && echo 0 || echo 1)" "$bad"

# pods: Running/Succeeded, and every container ready
bad=$(get pods -A | jq -r '
  .items[]
  | select(.status.phase != "Succeeded")
  | select(.status.phase != "Running"
           or ([.status.containerStatuses[]? | select(.ready | not)] | length) > 0)
  | "\(.metadata.namespace)/\(.metadata.name) (\(.status.phase))"' || echo "unreachable")
pods=$(get pods -A | jq -r '.items | length' || echo 0)
check "pods Running and Ready ($pods)" "$([ -z "$bad" ] && [ "$pods" -gt 0 ] && echo 0 || echo 1)" "$(echo "$bad" | tr '\n' ' ')"

# model: InferenceService Ready
bad=$(get inferenceservice -A | jq -r '
  .items[]
  | select(([.status.conditions[]? | select(.type=="Ready")][0].status) != "True")
  | "\(.metadata.namespace)/\(.metadata.name)"' || echo "unreachable")
n=$(get inferenceservice -A | jq -r '.items | length' || echo 0)
check "model InferenceService Ready ($n)" "$([ -z "$bad" ] && [ "$n" -gt 0 ] && echo 0 || echo 1)" "${bad:-none found}"

# Argo CD: Synced and Healthy
bad=$(get applications -n argocd | jq -r '
  .items[]
  | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
  | "\(.metadata.name) (\(.status.sync.status)/\(.status.health.status))"' || echo "unreachable")
n=$(get applications -n argocd | jq -r '.items | length' || echo 0)
check "Argo CD applications Synced and Healthy ($n)" "$([ -z "$bad" ] && [ "$n" -gt 0 ] && echo 0 || echo 1)" "${bad:-none found}"

# Gateway: Programmed
bad=$(get gateway -n kserve | jq -r '
  .items[]
  | select(([.status.conditions[]? | select(.type=="Programmed")][0].status) != "True")
  | .metadata.name' || echo "unreachable")
n=$(get gateway -n kserve | jq -r '.items | length' || echo 0)
check "Gateway Programmed ($n)" "$([ -z "$bad" ] && [ "$n" -gt 0 ] && echo 0 || echo 1)" "${bad:-none found}"

echo
if [ "$fail" -eq 0 ]; then echo "all healthy"; else echo "something is wrong"; fi
exit "$fail"
