# PyTorch GPU Training Example

A minimal GPU training job for validating the Kubeflow Training Operator and
NVIDIA GPU stack on this cluster. Uses a 3-layer fully-connected network
(784 → 256 → 128 → 10) trained on synthetic MNIST-sized data for 200 steps.

## Prerequisites

- Kubeflow installed (see [kubeflow-cv-lab](https://github.com/idvoretskyi/kubeflow-cv-lab) — `make platform-install`)
- GPU Operator running (`nvidia.com/gpu` capacity on GPU node)
- `kubectl` configured to the cluster context

## Run

```bash
# Submit
make apply

# Watch until done (polls every 10s)
make wait

# Confirm exit 0
make status

# Clean up
make clean
```

Or directly with kubectl:

```bash
kubectl apply -f pytorch-mnist-gpu.yaml
kubectl get pytorchjob pytorch-mnist-gpu -n kubeflow -w
```

## What it validates

| Check | Expected |
|---|---|
| PyTorchJob lifecycle | `Created → Running → Succeeded` |
| Container exit code | `0` |
| Scheduled node | GPU node (`nvidia.com/gpu` taint tolerated) |
| GPU resource | `nvidia.com/gpu: 1` requested and allocated |
| CUDA available | `True` — NVIDIA driver + container toolkit working |
| Training throughput | ~200 steps in < 60s on RTX 4000 Ada |

## Validation result (cluster lke609184, Kubeflow 26.03)

```
PyTorch version : 2.3.0+cu121
CUDA available  : True
GPU device      : NVIDIA RTX 4000 Ada Generation
GPU memory      : 13795 MB
Training on     : cuda
  step  50/200  loss=2.3036
  step 100/200  loss=2.2980
  step 150/200  loss=2.2859
  step 200/200  loss=2.2647
Training complete: 200 steps in ~40s (>1000 samples/s on cuda)
VALIDATION PASSED
```

## Customisation

- **Steps / batch size**: edit the `steps` and `batch_size` variables in the
  manifest's inline Python script.
- **Distributed training**: add a `Worker` replica spec alongside `Master` and
  set `replicas > 1` for multi-node data-parallel training.
- **Real dataset**: replace the synthetic `torch.randn` tensors with a
  `torchvision.datasets.MNIST` data loader.
