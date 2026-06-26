# kube-prometheus-stack Module

Installs the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm chart — a complete Kubernetes monitoring solution.

## Overview

Includes:

- **Prometheus** — metrics collection and storage
- **Grafana** — dashboards and visualization
- **Node Exporter** — hardware and OS metrics
- **Kube State Metrics** — Kubernetes object metrics
- **DCGM Exporter integration** — GPU metrics (when enabled)

Alertmanager is disabled by default. Storage uses `linode-block-storage-retain` to prevent data loss on pod restarts.

## Usage

```hcl
module "kube_prometheus_stack" {
  source = "./modules/kube-prometheus-stack"

  namespace               = "monitoring"
  grafana_admin_password  = "secure-password"
  prometheus_retention    = "7d"
  prometheus_storage_size = "15Gi"
  grafana_storage_size    = "5Gi"
  enable_gpu_monitoring   = true
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"monitoring"` |
| `kube_prometheus_stack_version` | Helm chart version | `"80.8.0"` |
| `grafana_admin_password` | Grafana admin password (sensitive) | — |
| `prometheus_retention` | Data retention period | `"15d"` |
| `prometheus_storage_size` | Prometheus PVC size | `"50Gi"` |
| `grafana_storage_size` | Grafana PVC size | `"10Gi"` |
| `storage_class` | Kubernetes StorageClass | `"linode-block-storage-retain"` |
| `enable_gpu_monitoring` | Add DCGM scrape config for GPU metrics | `false` |
| `node_selector` | nodeSelector to pin control-plane components (Prometheus, Grafana, kube-state-metrics, operator) onto a node pool. node-exporter stays cluster-wide. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Monitoring namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `grafana_service` | Grafana service name |
| `prometheus_service` | Prometheus service name |
| `prometheus_internal_url` | In-cluster Prometheus URL |
| `validation_commands` | Port-forward and access commands |

## Accessing the Stack

```bash
# Grafana (port 3000)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000  (default: admin / <grafana_admin_password>)

# Prometheus (port 9090)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090
```
