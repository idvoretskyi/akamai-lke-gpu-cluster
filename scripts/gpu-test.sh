#!/usr/bin/env bash
# Raw GPU smoke test: run nvidia-smi in a bare CUDA pod, print the output and
# clean up. The pod needs a whole GPU, so it stays Pending (and this script
# fails after 2 minutes) while the model server holds the only one.
#
# README "Scheduling" explains how to free the GPU on a one-GPU cluster (scaling
# the model down does not work; KServe and Argo CD put it back). Or add a second
# GPU node (gpu_node_count = 2).
#
# Usage: scripts/gpu-test.sh
set -euo pipefail

POD=gpu-test
trap 'kubectl delete pod "$POD" --ignore-not-found --wait=false >/dev/null' EXIT

kubectl delete pod "$POD" --ignore-not-found >/dev/null
kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $POD
spec:
  restartPolicy: Never
  nodeSelector:
    nodepool.lke/role: gpu
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  containers:
    - name: cuda
      image: nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: "1"
YAML

if ! kubectl wait "pod/$POD" --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s; then
  echo >&2
  echo "The pod did not finish. If it is Pending, the GPU is probably taken by the model:" >&2
  kubectl describe pod "$POD" | sed -n '/^Events:/,$p' >&2
  exit 1
fi
kubectl logs "pod/$POD"
