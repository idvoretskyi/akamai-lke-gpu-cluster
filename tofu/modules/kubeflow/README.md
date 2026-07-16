# Kubeflow Module

Installs the full [Kubeflow Platform](https://www.kubeflow.org/) using the
[`kubeflow/community-distribution`](https://github.com/kubeflow/community-distribution)
manifests (Pipelines, Katib, Notebooks, KServe, Trainer, Spark Operator, the
Central Dashboard, and required common services: Istio, Knative, cert-manager,
Dex, OAuth2-Proxy).

## Why this module doesn't use `helm_release` (unlike the other modules)

Every other module in this repo wraps a single Helm chart. Kubeflow doesn't
have one: the official distribution installs via `kustomize build | kubectl
apply`, and only a handful of individual components ship experimental Helm
charts (not the full platform). To install genuine, upstream-supported
Kubeflow, this module shells out to that same command via a `local-exec`
provisioner instead of `helm_release`.

Consequence: OpenTofu does **not** track the resulting Kubernetes objects in
state. `tofu apply` re-runs the install script (idempotent — `kubectl apply
--server-side`), and `tofu destroy` does not clean up Kubeflow objects
individually; per this repo's cost model, the whole LKE cluster is destroyed
instead.

## Prerequisites

- `kubectl`, `kustomize`, and `git` must be on `PATH` where `tofu apply` runs.
- Upstream recommends 16+ GB RAM / 8 CPU cores for the full platform across
  the cluster. Use `system_node_type = "g6-standard-4"` (see root
  `variables.tf`) and/or size the GPU node pool generously.
- Install can take 15–30 minutes; `kubectl apply` may need several retries
  while CRDs establish — the bundled `scripts/install.sh` handles this.

## Usage

```hcl
module "kubeflow" {
  source = "./modules/kubeflow"

  kubeflow_ref               = "master"
  k8s_host                   = local.k8s_auth.host
  k8s_token                  = local.k8s_auth.token
  k8s_cluster_ca_certificate = local.k8s_auth.cluster_ca_certificate

  depends_on = [module.hami, module.gpu_operator]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `kubeflow_ref` | Git tag/branch of `kubeflow/community-distribution` to install | `"master"` |
| `k8s_host` | Kubernetes API server URL | (required) |
| `k8s_token` | Kubernetes API bearer token | (required, sensitive) |
| `k8s_cluster_ca_certificate` | Cluster CA certificate (PEM) | (required, sensitive) |
| `install_timeout` | Timeout (seconds) per apply attempt | `1800` |

## Outputs

| Name | Description |
|---|---|
| `kubeflow_ref` | Git ref installed |
| `validation_commands` | Commands to check pods and reach the dashboard |

## Validation

```bash
kubectl get pods -n kubeflow
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
# http://localhost:8080 — user@example.com / 12341234 (default, lab-only credentials)
```

## GPU workloads under HAMi

Notebooks/pipelines requesting a GPU should set `schedulerName:
hami-scheduler` and request `nvidia.com/gpu` (+ optionally
`nvidia.com/gpumem` / `nvidia.com/gpucores`) instead of a whole GPU, and add
the toleration for the GPU node taint (`nvidia.com/gpu=present:NoSchedule`
when `dedicate_gpu_nodes = true`).

## Notes

- Lab/experimental setup: default static credentials (`user@example.com` /
  `12341234`) are used — do not expose this cluster's ingress publicly without
  changing them (see upstream README, "Change Default User Password").
- `install_kubeflow` defaults to `false` — it's heavy for a lab cluster; flip
  it on deliberately.
