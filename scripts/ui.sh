#!/usr/bin/env bash
# Open a UI on localhost with kubectl port-forward (nothing is public).
# Runs until you press Ctrl-C. Prints the login where there is one.
#
# Usage: scripts/ui.sh argocd|grafana|prometheus
#   argocd      http://localhost:8081   user admin
#   grafana     http://localhost:3000   user admin
#   prometheus  http://localhost:9090
set -euo pipefail

case "${1:-}" in
  argocd)
    ns=argocd svc=argo-cd-argocd-server from=8081 to=80
    echo "user: admin"
    echo "password: $(kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d)"
    ;;
  grafana)
    ns=monitoring svc=kube-prometheus-stack-grafana from=3000 to=80
    echo "user: admin"
    echo "password: $(kubectl -n monitoring get secret kube-prometheus-stack-grafana \
      -o jsonpath='{.data.admin-password}' | base64 -d)"
    ;;
  prometheus)
    ns=monitoring svc=kube-prometheus-stack-prometheus from=9090 to=9090
    ;;
  *)
    echo "usage: $0 argocd|grafana|prometheus" >&2
    exit 2
    ;;
esac

echo "http://localhost:$from   (Ctrl-C to stop)"
exec kubectl port-forward -n "$ns" "svc/$svc" "$from:$to"
