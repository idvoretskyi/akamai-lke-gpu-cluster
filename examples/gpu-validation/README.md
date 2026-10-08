# GPU Substrate Validation

A minimal GPU smoke test. Runs `nvidia-smi` in a bare CUDA
Pod to confirm the GPU substrate is working immediately after `tofu apply`.

**No prerequisites beyond the GPU Operator.** Just a kubeconfig and `kubectl`.

> **Note:** with this repo's default `install_hami = true`, HAMi's admission
> webhook intercepts this Pod too (it requests `nvidia.com/gpu` like any
> other workload) and caps its visible GPU memory at `hami_default_gpu_memory`
> (default **4000 MiB**), not the full ~20 GB card. That's expected — see
> `tofu/modules/hami/README.md`. Set `install_hami = false` (or
> `hami_default_gpu_memory = 0`) to validate the raw, unvirtualized substrate
> instead.

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

- [`../hami-validation/`](../hami-validation/) — two pods sharing the card.
- [`../argo-gpu-job/`](../argo-gpu-job/) — a GPU step in an Argo Workflow.
- [`../ollama/`](../ollama/) — chat with the models served from the GPU.
