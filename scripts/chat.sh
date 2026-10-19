#!/usr/bin/env bash
# Ask the model a question. Opens a temporary port-forward to the private
# Envoy Gateway, sends one OpenAI-style chat request, prints the reply, and
# closes the port-forward again.
#
# Usage:   scripts/chat.sh "Why is the sky blue?"
#          scripts/chat.sh                      # uses a default question
# Env:     MODEL=qwen3  NAMESPACE=vllm  MAX_TOKENS=512
#
# Qwen3 "thinks" before it answers; add /no_think to the prompt to skip that.
set -euo pipefail

PROMPT="${1:-Explain in two sentences what KServe does. /no_think}"
MODEL="${MODEL:-qwen3}"
NAMESPACE="${NAMESPACE:-vllm}"
MAX_TOKENS="${MAX_TOKENS:-512}"
GATEWAY_NS=envoy-gateway-system
GATEWAY=kserve-ingress-gateway

svc=$(kubectl get svc -n "$GATEWAY_NS" \
  -l "gateway.envoyproxy.io/owning-gateway-name=$GATEWAY" -o name | head -n1)
if [ -z "$svc" ]; then
  echo "No Envoy service for gateway '$GATEWAY' in $GATEWAY_NS. Is the cluster up? (scripts/status.sh)" >&2
  exit 1
fi

# Let kubectl pick a free local port (":80") instead of a fixed one: a fixed
# port that something else already listens on would make the port-forward fail
# while the readiness probe happily connected to that other service, and the
# prompt would be sent to it. The port is read from kubectl's own output.
log=$(mktemp)
kubectl port-forward -n "$GATEWAY_NS" "$svc" :80 >"$log" 2>&1 &
pf=$!
trap 'kill "$pf" 2>/dev/null || true; rm -f "$log"' EXIT

port=
for _ in $(seq 1 60); do
  if ! kill -0 "$pf" 2>/dev/null; then
    echo "port-forward failed:" >&2
    cat "$log" >&2
    exit 1
  fi
  port=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> .*/\1/p' "$log" | head -n1)
  [ -n "$port" ] && break
  sleep 0.5
done
if [ -z "$port" ]; then
  echo "port-forward did not become ready:" >&2
  cat "$log" >&2
  exit 1
fi

# The prompt travels through the environment into jq, never through the shell.
PROMPT="$PROMPT" jq -n --arg m "$MODEL" --argjson n "$MAX_TOKENS" \
  '{model: $m, max_tokens: $n, messages: [{role: "user", content: env.PROMPT}]}' |
  curl -sS --fail-with-body "http://127.0.0.1:$port/$NAMESPACE/$MODEL/v1/chat/completions" \
    -H 'Content-Type: application/json' -d @- |
  jq -r '.choices[0].message.content, "-- tokens: \(.usage.prompt_tokens) in / \(.usage.completion_tokens) out"'
