# OpenCost Module

Installs [OpenCost](https://www.opencost.io/) — a CNCF sandbox project for real-time Kubernetes cost monitoring.

## Overview

OpenCost provides:

- Per-namespace, per-pod, per-deployment cost allocation
- GPU and CPU/RAM cost breakdown
- Integration with Prometheus (via kube-prometheus-stack)
- Web UI for cost visualization

## Requirements

- Kubernetes cluster (1.21+)
- Prometheus (deployed via the `kube-prometheus-stack` module)

## Usage

```hcl
module "opencost" {
  source = "./modules/opencost"

  namespace              = "opencost"
  opencost_chart_version = "2.5.14"
  prometheus_url         = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
  enable_service_monitor = true

  depends_on = [module.kube_prometheus_stack]
}
```

## Accessing OpenCost

```bash
# Port-forward the OpenCost UI (port 9090)
kubectl port-forward --namespace opencost service/opencost 9090:9090

# Open UI in browser
# http://localhost:9090

# Query cost allocation API
curl http://localhost:9003/allocation/compute?window=60m
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"opencost"` |
| `opencost_chart_version` | Helm chart version | `"2.5.14"` |
| `prometheus_url` | In-cluster Prometheus URL | `"http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"` |
| `enable_ui` | Enable web UI | `true` |
| `enable_service_monitor` | Create Prometheus ServiceMonitor | `true` |
| `resources` | CPU/memory requests and limits | See variables.tf |
| `node_selector` | nodeSelector to pin the OpenCost pod onto a node pool (e.g. the system pool) | `{}` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | OpenCost namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `service_name` | Service name for port-forwarding |
| `validation_commands` | Port-forward and access commands |

## Notes

- OpenCost does not have a built-in Linode/Akamai cost provider. It uses Kubernetes resource consumption data from Prometheus and applies default pricing heuristics. For accurate Linode cost attribution, a [custom pricing ConfigMap](https://www.opencost.io/docs/configuration/on-prem) can be added.
- The UI is accessible only via `kubectl port-forward` (no firewall rule needed).
