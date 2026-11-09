#!/usr/bin/env bash
# Add the GPU pool back and wait for the model (LLMInferenceService) to be
# Ready. The node, image and weights take ~15 min.
#
# Usage: scripts/gpu-up.sh [timeout, default 30m]
set -euo pipefail

timeout="${1:-30m}"

cd "$(dirname "${BASH_SOURCE[0]}")/../tofu"
tofu apply -auto-approve -var gpu_enabled=true

kubectl wait llmisvc --all -n vllm --for=condition=Ready --timeout="$timeout"
