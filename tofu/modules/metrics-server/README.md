# Metrics Server Module

Installs [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server) to provide the resource metrics API.

## Overview

Metrics Server enables:

- `kubectl top nodes` / `kubectl top pods`
- Horizontal Pod Autoscaler (HPA) scaling decisions
- Vertical Pod Autoscaler (VPA) recommendations

Configured for Linode LKE compatibility (`--kubelet-insecure-tls`, `--kubelet-preferred-address-types=InternalIP`).

## Usage

```hcl
module "metrics_server" {
  source = "./modules/metrics-server"

  namespace = "kube-system"
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"kube-system"` |
| `metrics_server_version` | Helm chart version | `"3.12.2"` |
| `replicas` | Number of replicas (2 for HA) | `2` |
| `resources` | CPU/memory requests and limits | See variables.tf |
| `node_selector` | nodeSelector to pin pods onto a node pool (e.g. the system pool) | `{}` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Metrics Server namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `validation_commands` | Commands to validate Metrics Server |

## Validation

```bash
# Check Metrics Server pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

# Test resource metrics
kubectl top nodes
kubectl top pods -A

# Verify API availability
kubectl get apiservices v1beta1.metrics.k8s.io
```
