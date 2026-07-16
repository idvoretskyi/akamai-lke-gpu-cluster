# GPU Operator Module

Installs the [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/) for automated GPU driver and device plugin management.

## Overview

The GPU Operator provides:

- Automated NVIDIA driver installation
- GPU device plugin for Kubernetes resource scheduling
- DCGM Exporter for Prometheus GPU metrics
- GPU Feature Discovery (GFD)
- Node Status Exporter
- Validation workloads

This module is optimised for **NVIDIA RTX 4000 Ada** (MIG disabled, containerd runtime — supports containerd 2.x config version 3).

## Usage

```hcl
module "gpu_operator" {
  source = "./modules/gpu-operator"

  namespace                   = "gpu-operator"
  gpu_operator_version        = "v26.3.2"
  install_driver              = true
  device_plugin_enabled       = true
  enable_dcgm_exporter        = true
  enable_node_status_exporter = true
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"gpu-operator"` |
| `gpu_operator_version` | Helm chart version (`vX.Y.Z`) | `"v26.3.2"` |
| `install_driver` | Install NVIDIA driver | `true` |
| `device_plugin_enabled` | Enable the stock NVIDIA device plugin; set `false` when HAMi manages GPU scheduling instead | `true` |
| `enable_dcgm_exporter` | Enable DCGM Exporter for GPU metrics | `true` |
| `enable_node_status_exporter` | Enable Node Status Exporter | `true` |
| `controller_node_selector` | nodeSelector to pin the operator controller (e.g. the system pool) | `{}` |
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
