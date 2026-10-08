# Argo Workflows Module

Installs [Argo Workflows](https://argoproj.github.io/workflows/) — a CNCF
graduated, Kubernetes-native workflow engine — via the `argo/argo-workflows`
Helm chart.

## Overview

- Controller and server run on the system pool.
- Workflows run in the release namespace (`singleNamespace`), as the
  `argo-workflow` service account (created with a Role/RoleBinding).
- GPU steps are scheduled onto the GPU pool by the Workflow spec (toleration +
  `nvidia.com/gpu` limit). With HAMi they get a vGPU slice and share the card
  with Ollama. See [`examples/argo-gpu-job`](../../../examples/argo-gpu-job/).

## Usage

```hcl
module "argo_workflows" {
  source = "./modules/argo-workflows"

  namespace     = "argo"
  chart_version = "2.0.11"
  node_selector = local.system_node_selector
}
```

## Accessing the UI

```bash
kubectl port-forward -n argo service/argo-workflows-server 2746:2746
# http://localhost:2746
```

The default `auth_mode = "server"` needs no login, so keep the UI behind
`kubectl port-forward`. Use `auth_mode = "client"` to require a token.

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Namespace (workflows run here too) | `"argo"` |
| `chart_version` | `argo/argo-workflows` chart version | `"2.0.11"` |
| `timeout` | Helm wait timeout (s) | `600` |
| `auth_mode` | `server` or `client` | `"server"` |
| `enable_service_monitor` | Create a controller ServiceMonitor (needs the Prometheus CRDs) | `false` |
| `node_selector` | Node selector for controller and server | `{}` |
| `resources` | Requests/limits for controller and server | 50m/128Mi, 250m/256Mi |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `service_account` | Service account workflows run as |
| `validation_commands` | Port-forward and verification commands |
