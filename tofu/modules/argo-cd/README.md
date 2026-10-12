# Argo CD Module

Installs [Argo CD](https://argo-cd.readthedocs.io/) (CNCF graduated) and the
bootstrap Applications that hand workloads over to GitOps.

## Overview

Two Helm releases:

1. `argo-cd` (`argo/argo-cd`): a single-replica lab install. Dex and the
   notifications controller are off; the server speaks plain HTTP
   (`server.insecure`) because it is only reached through
   `kubectl port-forward`. With `enable_service_monitor`, the controller,
   server, repo server and ApplicationSet controller get ServiceMonitors.
2. `argo-cd-applications` (the local chart in `chart/`, only when
   `applications` is non-empty): one `Application` per entry, syncing a Git
   directory into a namespace with automated prune and self-heal,
   `CreateNamespace`, server-side apply and retries. Each carries the
   `resources-finalizer.argocd.argoproj.io` finalizer, so destroying the
   release deletes what the Application synced.

In this repository the root module passes one Application, `vllm`, which
syncs `gitops/vllm` (the KServe InferenceService).

## Usage

```hcl
module "argo_cd" {
  source = "./modules/argo-cd"

  namespace              = "argocd"
  chart_version          = "10.10.1"
  node_selector          = { "nodepool.lke/role" = "system" }
  enable_service_monitor = true

  applications = [{
    name            = "vllm"
    namespace       = "vllm"
    repo_url        = "https://github.com/idvoretskyi/akamai-lke-gpu-cluster.git"
    target_revision = "main"
    path            = "gitops/vllm"
  }]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"argocd"` |
| `chart_version` | argo/argo-cd chart version | `"10.10.1"` |
| `node_selector` | nodeSelector for every Argo CD component | `{}` |
| `enable_service_monitor` | Metrics + ServiceMonitors | `false` |
| `applications` | Bootstrap Applications (`name`, `namespace`, `repo_url`, `target_revision`, `path`) | `[]` |
| `timeout` | Helm install/upgrade timeout (s) | `600` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Argo CD namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `application_names` | Names of the bootstrap Applications |
| `validation_commands` | Commands to validate Argo CD |

## Validation

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd     # Synced / Healthy
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward -n argocd svc/argo-cd-argocd-server 8081:80
```
