#!/usr/bin/env bash
# Ask the model a question. Opens a temporary port-forward to the private
# Envoy Gateway, sends one OpenAI-style chat request, prints the reply, and
# closes the port-forward again.
#
# Usage:   scripts/chat.sh "Why is the sky blue?"
#          scripts/chat.sh                      # uses a default question
# Env:     PORT=8080  MODEL=qwen3  NAMESPACE=vllm  DOMAIN=kserve.local
#          MAX_TOKENS=512
#
# Qwen3 "thinks" before it answers; add /no_think to the prompt to skip that.
set -euo pipefail

PROMPT="${1:-Explain in two sentences what KServe does. /no_think}"
PORT="${PORT:-8080}"
MODEL="${MODEL:-qwen3}"
NAMESPACE="${NAMESPACE:-vllm}"
DOMAIN="${DOMAIN:-kserve.local}"
MAX_TOKENS="${MAX_TOKENS:-512}"
GATEWAY_NS=envoy-gateway-system
GATEWAY=kserve-ingress-gateway

svc=$(kubectl get svc -n "$GATEWAY_NS" \
  -l "gateway.envoyproxy.io/owning-gateway-name=$GATEWAY" -o name | head -n1)
if [ -z "$svc" ]; then
  echo "No Envoy service for gateway '$GATEWAY' in $GATEWAY_NS. Is the cluster up? (scripts/status.sh)" >&2
  exit 1
fi

kubectl port-forward -n "$GATEWAY_NS" "$svc" "$PORT:80" >/dev/null 2>&1 &
pf=$!
trap 'kill "$pf" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break
  sleep 0.5
done

# The prompt travels through the environment into jq, never through the shell.
PROMPT="$PROMPT" jq -n --arg m "$MODEL" --argjson n "$MAX_TOKENS" \
  '{model: $m, max_tokens: $n, messages: [{role: "user", content: env.PROMPT}]}' |
  curl -sS --fail-with-body "http://127.0.0.1:$PORT/openai/v1/chat/completions" \
    -H "Host: $MODEL-$NAMESPACE.$DOMAIN" -H 'Content-Type: application/json' -d @- |
  jq -r '.choices[0].message.content, "-- tokens: \(.usage.prompt_tokens) in / \(.usage.completion_tokens) out"'
