# GPU Operator Module

Installs the [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/) for GPU device plugin, monitoring and validation on nodes whose NVIDIA driver and container toolkit are pre-installed.

## Overview

The GPU Operator provides:

- Optional NVIDIA driver and container toolkit installation (both off on LKE)
- GPU device plugin for Kubernetes resource scheduling
- DCGM Exporter for Prometheus GPU metrics
- GPU Feature Discovery (GFD)
- Node Status Exporter
- Validation workloads

This module is optimised for **NVIDIA RTX 4000 Ada** (MIG disabled, containerd runtime).

LKE GPU nodes ship the NVIDIA driver, the container toolkit and a containerd
`nvidia` runtime. Keep `install_driver = false` and `install_toolkit = false`
there: the operator's toolkit rewrites `/etc/containerd/conf.d/99-nvidia.toml`
and restarts containerd, which then fails to start and leaves the node
`NotReady`.

## Usage

```hcl
module "gpu_operator" {
  source = "./modules/gpu-operator"

  namespace                   = "gpu-operator"
  chart_version               = "v26.7.1"
  install_driver              = false
  install_toolkit             = false
  device_plugin_enabled       = true
  enable_dcgm_exporter        = true
  enable_node_status_exporter = true
  node_selector               = local.system_node_selector
  gpu_node_toleration         = local.gpu_node_toleration
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"gpu-operator"` |
| `chart_version` | Helm chart version (`vX.Y.Z`) | `"v26.7.1"` |
| `install_driver` | Install NVIDIA driver (LKE nodes ship it) | `false` |
| `install_toolkit` | Install the NVIDIA Container Toolkit (rewrites containerd config) | `false` |
| `device_plugin_enabled` | Enable the stock NVIDIA device plugin; set `false` only if another device plugin advertises `nvidia.com/gpu` | `true` |
| `enable_dcgm_exporter` | Enable DCGM Exporter for GPU metrics | `true` |
| `enable_node_status_exporter` | Enable Node Status Exporter | `true` |
| `node_selector` | nodeSelector to pin the operator controller (e.g. the system pool) | `{}` |
| `gpu_node_toleration` | GPU node taint (`key`/`value`/`effect`) the operands tolerate; `null` when untainted | `null` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | GPU Operator namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `validation_commands` | Commands to validate GPU availability |

## Validation

```bash
# Check GPU operator pods
kubectl get pods -n gpu-operator

# Verify GPU devices on nodes
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'

# Run a GPU test workload (kubectl run --limits=... was removed in
# kubectl 1.24+ — use the tested manifest in examples/gpu-validation instead)
kubectl apply -f examples/gpu-validation/nvidia-smi-pod.yaml
kubectl wait pod/gpu-validation --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
kubectl logs pod/gpu-validation
```
