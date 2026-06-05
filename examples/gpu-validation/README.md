# GPU Substrate Validation

A minimal, **Kubeflow-free** GPU smoke test. Runs `nvidia-smi` in a bare CUDA
Pod to confirm the GPU substrate is working immediately after `tofu apply`.

**No prerequisites beyond the GPU Operator.** Does not require Kubeflow,
MLflow, or any ML platform — just a kubeconfig and `kubectl`.

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

Once this passes, install Kubeflow and run the full ML platform smoke tests
from [`kubeflow-cv-lab`](https://github.com/idvoretskyi/kubeflow-cv-lab):

```bash
# Install Kubeflow
git clone https://github.com/idvoretskyi/kubeflow-cv-lab
PRESET=lke make -C kubeflow-cv-lab platform-install

# Run Trainer v2 GPU example (requires Kubeflow)
# See examples/pytorch-training/ in kubeflow-cv-lab
```
