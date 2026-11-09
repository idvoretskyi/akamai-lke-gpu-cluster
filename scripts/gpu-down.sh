#!/usr/bin/env bash
# Remove the GPU pool to stop paying for the GPU (~$0.52/hr). The cluster and
# platform stay up; the model stays Pending until scripts/gpu-up.sh.
#
# Usage: scripts/gpu-down.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../tofu"
tofu apply -auto-approve -var gpu_enabled=false
