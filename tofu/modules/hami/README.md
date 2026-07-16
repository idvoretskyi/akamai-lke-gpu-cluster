# HAMi Module

Installs [HAMi](https://github.com/Project-HAMi/HAMi) (Heterogeneous AI
Computing Virtualization middleware) for GPU sharing/virtualization on top of
the NVIDIA GPU Operator.

## Overview

HAMi replaces the stock NVIDIA device plugin with a vGPU-aware one and adds a
scheduler extender + mutating webhook, so that:

- A single physical GPU can be split into multiple schedulable slices
  (`device_split_count`), letting several pods share one GPU.
- GPU memory (`nvidia.com/gpumem`) and compute cores (`nvidia.com/gpucores`)
  can be requested as fine-grained resources instead of whole GPUs.
- The scheduler enforces isolation between co-scheduled workloads sharing the
  same physical device.

This module depends on the **GPU Operator** for the NVIDIA driver, container
toolkit, and DCGM/GFD — HAMi only takes over the device-plugin and scheduling
layer (see `device_plugin_enabled` on the `gpu-operator` module, which the
root module sets to `false` when HAMi is installed).

## Usage

```hcl
module "hami" {
  source = "./modules/hami"

  namespace             = "hami-system"
  hami_version          = "2.9.0"
  device_split_count    = 10
  device_memory_scaling = 1
  scheduler_policy      = "binpack"
  nvidia_node_selector  = local.gpu_node_labels

  depends_on = [module.gpu_operator]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"hami-system"` |
| `hami_version` | Helm chart version (`X.Y.Z`) | `"2.9.0"` |
| `device_split_count` | vGPU slices per physical GPU | `10` |
| `device_memory_scaling` | GPU memory oversubscription ratio | `1` |
| `device_core_scaling` | GPU compute-core oversubscription ratio | `1` |
| `scheduler_policy` | `binpack` or `spread` | `"binpack"` |
| `node_selector` | nodeSelector for HAMi control-plane bits (webhook cert job) | `{}` |
| `gpu_node_toleration` | GPU node taint the devicePlugin tolerates; `null` when untainted | `null` |
| `nvidia_node_selector` | nodeSelector the devicePlugin uses to target GPU nodes | `{ gpu = "on" }` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | HAMi namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `validation_commands` | Commands to validate GPU virtualization |

## Validation

```bash
# Check HAMi pods
kubectl get pods -n hami-system

# Two pods sharing one physical GPU, each requesting a memory slice
kubectl run hami-test --rm -it --restart=Never \
  --overrides='{"spec":{"schedulerName":"hami-scheduler"}}' \
  --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1,nvidia.com/gpumem=2000 \
  -- nvidia-smi
```

Pods that want a HAMi-managed GPU slice must set `schedulerName:
hami-scheduler` and request `nvidia.com/gpu` (+ optionally `nvidia.com/gpumem`
/ `nvidia.com/gpucores`) instead of relying on the default scheduler.

## Notes

- This is a lab/experimental setup — HAMi is enabled by default
  (`install_hami = true`) since the cluster is destroyed/recreated freely and
  there's no in-place migration concern.
- MIG remains disabled on the GPU Operator side; HAMi's software-level
  splitting (`hami-core` mode) is used instead, which works on GPUs without
  MIG support (e.g. RTX 4000 Ada).
