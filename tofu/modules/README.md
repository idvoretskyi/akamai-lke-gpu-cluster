# OpenTofu Modules

Reusable OpenTofu modules for GPU-enabled Kubernetes infrastructure on Linode (LKE).

## Modules

| Module | Purpose | Directory |
|---|---|---|
| [gpu-operator](gpu-operator/README.md) | NVIDIA GPU Operator — automated driver & device plugin | `gpu-operator/` |
| [hami](hami/README.md) | HAMi — GPU virtualization/sharing (vGPU slices) | `hami/` |
| [kubeflow](kubeflow/README.md) | Full Kubeflow Platform (opt-in, kustomize-based) | `kubeflow/` |
| [metrics-server](metrics-server/README.md) | Kubernetes Metrics Server — `kubectl top` & HPA | `metrics-server/` |
| [kube-prometheus-stack](kube-prometheus-stack/README.md) | Prometheus + Grafana + Alertmanager monitoring stack | `kube-prometheus-stack/` |
| [opencost](opencost/README.md) | OpenCost — Kubernetes cost monitoring | `opencost/` |

## Dependency Graph

All modules' `kubernetes`/`helm` provider configs key off
`linode_lke_cluster.gpu_cluster`'s kubeconfig (`local.k8s_auth`), but that's
implicit provider wiring, not a module `depends_on`. Explicit `depends_on`
edges between modules (`tofu/modules.tf`):

```text
module.gpu_operator
    ├─> module.hami ─────────────────┐
    ├─> module.kube_prometheus_stack │
    └─> module.kubeflow <────────────┘
module.metrics_server
    └─> module.kube_prometheus_stack
            └─> module.opencost
```

`terraform_data.merge_kubeconfig` (writes `~/.kube/config`, `tofu/kubeconfig.tf`)
is independent — no module depends on it, and disabling it
(`merge_kubeconfig = false`) doesn't affect any module install.

All modules are optional and independently toggled via `install_*` root variables.

See the root [README.md](../../README.md#accessing-services) for
port-forward/access commands.
