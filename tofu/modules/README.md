# OpenTofu Modules

Reusable OpenTofu modules for GPU-enabled Kubernetes infrastructure on Linode (LKE).

## Modules

| Module | Purpose | Directory |
|---|---|---|
| [gpu-operator](gpu-operator/README.md) | NVIDIA GPU Operator — automated driver & device plugin | `gpu-operator/` |
| [metrics-server](metrics-server/README.md) | Kubernetes Metrics Server — `kubectl top` & HPA | `metrics-server/` |
| [kube-prometheus-stack](kube-prometheus-stack/README.md) | Prometheus + Grafana + Alertmanager monitoring stack | `kube-prometheus-stack/` |
| [opencost](opencost/README.md) | OpenCost — Kubernetes cost monitoring | `opencost/` |
| [kubeflow](kubeflow/README.md) | Full Kubeflow Platform (Istio, Dex, Dashboard, Notebooks, Katib, KServe, Pipelines) | `kubeflow/` |

## Dependency Graph

```text
linode_lke_cluster
    └─> terraform_data.merge_kubeconfig
        ├─> module.gpu_operator
        │       └─> module.kubeflow        # full Kubeflow Platform (optional)
        ├─> module.metrics_server
        ├─> module.kube_prometheus_stack
        │       └─> module.opencost
        └─> (kubeconfig written to ~/.kube/config)
```

All modules are optional and independently toggled via `install_*` root variables.

## Quick Reference

```bash
# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Access OpenCost UI
kubectl port-forward -n opencost svc/opencost 9090:9090

# Check GPU availability
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'

# Resource usage
kubectl top nodes && kubectl top pods -A
```
