# OpenTofu Modules

Reusable OpenTofu modules for GPU-enabled Kubernetes infrastructure on Linode (LKE).

## Modules

| Module | Purpose | Directory |
|---|---|---|
| [gpu-operator](gpu-operator/README.md) | NVIDIA GPU Operator (operands only; LKE ships the driver) | `gpu-operator/` |
| [hami](hami/README.md) | HAMi — GPU sharing (vGPU slices) | `hami/` |
| [ollama](ollama/README.md) | Ollama — local LLM serving on the GPU pool | `ollama/` |
| [argo-workflows](argo-workflows/README.md) | Argo Workflows — CNCF workflow engine | `argo-workflows/` |
| [open-webui](open-webui/README.md) | Open WebUI — browser front-end for Ollama (opt-in) | `open-webui/` |
| [metrics-server](metrics-server/README.md) | Kubernetes Metrics Server — `kubectl top` & HPA | `metrics-server/` |
| [kube-prometheus-stack](kube-prometheus-stack/README.md) | Prometheus + Grafana monitoring stack | `kube-prometheus-stack/` |
| [opencost](opencost/README.md) | OpenCost — Kubernetes cost monitoring | `opencost/` |

## Dependency Graph

All modules' `kubernetes`/`helm` provider configs key off
`linode_lke_cluster.gpu_cluster`'s kubeconfig (`local.k8s_auth`), but that's
implicit provider wiring, not a module `depends_on`. Explicit `depends_on`
edges between modules (`tofu/modules.tf`):

```text
module.gpu_operator
    ├─> module.hami
    │       └─> module.ollama
    │               └─> module.open_webui
    ├─> module.kube_prometheus_stack
    │       ├─> module.argo_workflows
    │       └─> module.opencost
    └─> module.ollama
module.metrics_server
    └─> module.kube_prometheus_stack
```

`terraform_data.merge_kubeconfig` (writes `~/.kube/config`, `tofu/kubeconfig.tf`)
is independent — no module depends on it, and disabling it
(`merge_kubeconfig = false`) doesn't affect any module install.

All modules are optional and independently toggled via `install_*` root variables.

For port-forward commands and other access, see the root `README.md`; each
module's `validation_commands` output prints the exact commands.
