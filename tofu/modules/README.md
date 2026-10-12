# OpenTofu Modules

One module per platform component, each wrapping a Helm chart on Linode LKE.

## Modules

| Module | Purpose | Directory |
|---|---|---|
| [gpu-operator](gpu-operator/README.md) | NVIDIA GPU Operator: device plugin, GFD, DCGM (LKE ships the driver) | `gpu-operator/` |
| [metrics-server](metrics-server/README.md) | Kubernetes Metrics Server: `kubectl top` and HPA | `metrics-server/` |
| [kube-prometheus-stack](kube-prometheus-stack/README.md) | Prometheus + Grafana; scrapes every ServiceMonitor and DCGM | `kube-prometheus-stack/` |
| [cert-manager](cert-manager/README.md) | Certificates for KServe's admission webhooks | `cert-manager/` |
| [envoy-gateway](envoy-gateway/README.md) | Gateway API CRDs, Envoy Gateway and the `envoy` GatewayClass | `envoy-gateway/` |
| [kserve](kserve/README.md) | KServe control plane (Standard mode, Gateway API) and the vLLM runtime | `kserve/` |
| [argo-cd](argo-cd/README.md) | Argo CD and its bootstrap Applications | `argo-cd/` |

Workloads (the InferenceService) are not modules: they live in
[`gitops/`](../../gitops/) and are synced by Argo CD.

## Dependency Graph

All modules' `kubernetes`/`helm` provider configs key off
`linode_lke_cluster.gpu_cluster`'s kubeconfig (`local.k8s_auth`), but that's
implicit provider wiring, not a module `depends_on`. Explicit `depends_on`
edges between modules (`tofu/modules.tf`):

```text
module.gpu_operator ─────┬─> module.kube_prometheus_stack ─┬─> module.cert_manager ──┐
module.metrics_server ───┘                                 ├─> module.envoy_gateway ─┼─> module.kserve ─> module.argo_cd
                                                           └─────────────────────────┼──────────────────> module.argo_cd
module.gpu_operator ─────────────────────────────────────────────────────────────────┘
```

- kube-prometheus-stack comes first among the add-ons so the ServiceMonitor CRD
  exists when cert-manager and Argo CD create ServiceMonitors.
- KServe needs cert-manager (webhook certificate) and Envoy Gateway (the
  `envoy` GatewayClass its Gateway uses).
- Argo CD depends on KServe so that on `tofu destroy` its Application, and the
  InferenceService it synced, are deleted while KServe is still running.

`terraform_data.merge_kubeconfig` (writes `~/.kube/config`, `tofu/kubeconfig.tf`)
is independent — no module depends on it, and disabling it
(`merge_kubeconfig = false`) doesn't affect any module install.

## Custom resources from OpenTofu

The GatewayClass/EnvoyProxy (envoy-gateway) and the Argo CD Applications
(argo-cd) are custom resources whose CRDs only exist once the module's main
chart is installed, so `kubernetes_manifest` can't plan them on a fresh
cluster. Each of those modules ships a small local Helm chart in `chart/` and
installs it as a second `helm_release` after the first. CI lints and renders
these charts.

## Toggles

Each module is toggled by a root `install_*` variable; `install_kserve`
covers cert-manager, Envoy Gateway and KServe together.

For port-forward commands and other access, see the root `README.md`; each
module's `validation_commands` output prints the exact commands.
