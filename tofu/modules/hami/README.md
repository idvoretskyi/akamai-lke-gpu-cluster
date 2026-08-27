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

`kubectl` must be on `PATH` — it's always used to restart `hami-scheduler`
after patching its config (see "Memory slicing defaults" below), which the
module manages unconditionally (including to reset back to the chart's
whole-GPU default when `default_gpu_memory = 0`).

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

  default_gpu_memory         = 8000
  k8s_host                   = local.k8s_auth.host
  k8s_token                  = local.k8s_auth.token
  k8s_cluster_ca_certificate = local.k8s_auth.cluster_ca_certificate

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
| `default_gpu_memory` | vGPU memory (MB) given to `nvidia.com/gpu` requests with no explicit `gpumem`; `0` disables (whole-GPU) | `8000` |
| `node_selector` | nodeSelector for HAMi control-plane bits (webhook cert job) | `{}` |
| `gpu_node_toleration` | GPU node taint the devicePlugin tolerates; `null` when untainted | `null` |
| `nvidia_node_selector` | nodeSelector the devicePlugin uses to target GPU nodes | `{ gpu = "on" }` |
| `scheduler_leader_elect` | HAMi scheduler leader election; `false` avoids an anti-affinity deadlock on single-node system pools | `false` |
| `runtime_class_name` | RuntimeClass the devicePlugin (and HAMi-scheduled workloads) run under — must be a legacy/non-CDI NVIDIA runtime | `"nvidia-legacy"` |
| `nvidia_driver_root` | Host path where the GPU Operator's containerized driver is installed | `"/run/nvidia/driver"` |
| `wait_for_toolkit_ready` | Gate devicePlugin startup on the GPU Operator's toolkit readiness marker | `true` |
| `k8s_host` | Kubernetes API server URL | (required) |
| `k8s_token` | Kubernetes API bearer token | (required, sensitive) |
| `k8s_cluster_ca_certificate` | Cluster CA certificate (PEM) | (required, sensitive) |

## Outputs

| Name | Description |
|---|---|
| `namespace` | HAMi namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `validation_commands` | Commands to validate GPU virtualization |

## Memory slicing defaults (`default_gpu_memory`)

HAMi's chart (v2.9.0) hardcodes `nvidia.defaultMemory: 0` in the
`hami-scheduler-device` ConfigMap — there's no Helm value for it. A Pod that
requests `nvidia.com/gpu` without also specifying `nvidia.com/gpumem` then
gets the **whole physical GPU**, defeating the point of virtualization for
any workload that has no easy way to set that extra resource key (notably
Kubeflow Pipelines via the `kfp` SDK — see `examples/roboflow-pipeline`).

This module works around that by authoring the ConfigMap's `nvidia:` section
directly (`kubernetes_config_map_v1_data`, `force = true`) with our own
`default_gpu_memory` value, then restarting `hami-scheduler` — the scheduler
only reads this file at process startup, not on ConfigMap change, so a
restart is required for the new value to take effect. Both happen
automatically on every `tofu apply`, **unconditionally**, including when
`default_gpu_memory = 0`: restoring the chart's own whole-GPU default for
unslotted requests also needs the live ConfigMap reset and the scheduler
restarted, not just "do nothing".

## Validation

```bash
# Check HAMi pods
kubectl get pods -n hami-system

# Two pods sharing one physical GPU, each requesting an explicit memory slice
# (kubectl run --limits=... was removed in kubectl 1.24+ — use the tested
# manifest in examples/hami-validation instead)
kubectl apply -f examples/hami-validation/nvidia-smi-shared-pods.yaml
kubectl wait pod/hami-validation-a pod/hami-validation-b --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
kubectl logs hami-validation-a && kubectl logs hami-validation-b

# A Pod that only requests nvidia.com/gpu (no gpumem) gets default_gpu_memory
# instead of the whole card (8000 MiB below, with the default setting) — see
# examples/gpu-validation for the tested manifest:
kubectl apply -f examples/gpu-validation/nvidia-smi-pod.yaml
kubectl wait pod/gpu-validation --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
kubectl logs pod/gpu-validation
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
- `runtime_class_name` must be a **legacy (non-CDI) NVIDIA RuntimeClass**
  (default: `"nvidia-legacy"`, which the GPU Operator's toolkit registers
  alongside its own default `"nvidia"`). HAMi's GPU sharing relies on
  hijacking the driver library via `LD_PRELOAD` + `NVIDIA_VISIBLE_DEVICES`,
  which conflicts with the modern CDI-based device-injection path — the GPU
  Operator's default `"nvidia"` RuntimeClass has CDI enabled and fails to
  resolve HAMi's device references.
