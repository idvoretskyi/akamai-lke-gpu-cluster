# GPU Substrate Validation

A minimal GPU smoke test. Runs `nvidia-smi` in a bare CUDA
Pod to confirm the GPU substrate is working immediately after `tofu apply`.

**No prerequisites beyond the GPU Operator.** Just a kubeconfig and `kubectl`.

> **Note:** the pod needs a whole GPU. With the default stack the vLLM
> InferenceService already holds the only one, so this pod stays `Pending`.
> Run it before Argo CD syncs the model, temporarily remove the model (point
> `gitops_path` at an empty directory or delete the `vllm` Application), or
> add a second GPU node (`gpu_node_count = 2`).

## What it validates

| Check | Expected |
|---|---|
| GPU resource available | `nvidia.com/gpu: 1` allocatable on the GPU node |
| NVIDIA driver installed | `nvidia-smi` exits 0 |
| Container toolkit working | CUDA container schedules and runs |
| GPU node taint tolerated | Pod lands on tainted GPU node |

## Quick start

```bash
# Submit, wait, and print output
make apply
make wait
make logs

# Cleanup
make clean
```

Or directly with kubectl:

```bash
kubectl apply -f nvidia-smi-pod.yaml
kubectl wait pod/gpu-validation --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
kubectl logs pod/gpu-validation
kubectl delete pod/gpu-validation
```

## Expected output

```text
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 550.x.x    Driver Version: 550.x.x    CUDA Version: 12.4     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA RTX 4000 Ada ...        Off |   00000000:00:06.0 Off |                  Off |
...
+-----------------------------------------------------------------------------------------+
```

## After validation

- [`../kserve-chat/`](../kserve-chat/) — chat with the model served by KServe + vLLM.
- [`../argocd/`](../argocd/) — the GitOps view of the model.
