#!/usr/bin/env bash
# Reach something private on localhost with kubectl port-forward (nothing is
# public). Runs until you press Ctrl-C. Prints the login where there is one.
#
# Usage: scripts/ui.sh argocd|grafana|prometheus|model
#   argocd      http://localhost:8081            user admin
#   grafana     http://localhost:3000            user admin
#   prometheus  http://localhost:9090
#   model       http://localhost:8080/openai/v1  the OpenAI-compatible API, for
#               your own client (scripts/chat.sh needs none of this)
set -euo pipefail

case "${1:-}" in
  argocd)
    ns=argocd target=svc/argo-cd-argocd-server from=8081 to=80
    echo "user: admin"
    echo "password: $(kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d)"
    ;;
  grafana)
    ns=monitoring target=svc/kube-prometheus-stack-grafana from=3000 to=80
    echo "user: admin"
    echo "password: $(kubectl -n monitoring get secret kube-prometheus-stack-grafana \
      -o jsonpath='{.data.admin-password}' | base64 -d)"
    ;;
  prometheus)
    ns=monitoring target=svc/kube-prometheus-stack-prometheus from=9090 to=9090
    ;;
  model)
    ns=envoy-gateway-system from=8080 to=80
    target=$(kubectl get svc -n "$ns" \
      -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway -o name | head -n1)
    if [ -z "$target" ]; then
      echo "No Envoy service for the model Gateway. Is the cluster up? (scripts/status.sh)" >&2
      exit 1
    fi
    echo "base URL: http://localhost:8080/openai/v1"
    echo "model:    qwen3   (any API key)"
    echo "header:   Host: qwen3-vllm.kserve.local   (the Gateway routes on it)"
    ;;
  *)
    echo "usage: $0 argocd|grafana|prometheus|model" >&2
    exit 2
    ;;
esac

echo "http://localhost:$from   (Ctrl-C to stop)"
exec kubectl port-forward -n "$ns" "$target" "$from:$to"
