# Open WebUI Module

Installs [Open WebUI](https://github.com/open-webui/open-webui), a browser
front-end for Ollama, via the `open-webui/open-webui` Helm chart.

## Overview

- CPU-only; runs on the system pool and talks to the cluster's Ollama over its
  in-cluster service URL. The chart's bundled Ollama, Pipelines and Redis are
  disabled.
- Data (accounts, chats) lives on a small PVC using `linode-block-storage`
  (reclaim policy Delete), so it is removed on `tofu destroy`.
- Opt-in at the root: `install_open_webui = true` (requires `install_ollama`).

## Usage

```hcl
module "open_webui" {
  source = "./modules/open-webui"

  namespace     = "open-webui"
  chart_version = "16.6.0"
  ollama_url    = "http://ollama.ollama.svc.cluster.local:11434"
  node_selector = local.system_node_selector
}
```

## Accessing the UI

```bash
kubectl port-forward -n open-webui service/open-webui 8080:80
# http://localhost:8080
```

The first account you create becomes the admin. Set `enable_signup = false`
afterwards.

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Namespace | `"open-webui"` |
| `chart_version` | `open-webui/open-webui` chart version | `"16.6.0"` |
| `timeout` | Helm wait timeout (s) | `600` |
| `ollama_url` | In-cluster Ollama API URL | `"http://ollama.ollama.svc.cluster.local:11434"` |
| `storage_size` | Data PVC size | `"5Gi"` |
| `storage_class` | Data PVC storage class | `"linode-block-storage"` |
| `enable_signup` | Allow sign-ups (first account is admin) | `true` |
| `node_selector` | Node selector | `{}` |
| `resources` | Requests/limits | 100m/512Mi, 1000m/1Gi |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `service_name` | Service name (for port-forward) |
| `validation_commands` | Port-forward and verification commands |
