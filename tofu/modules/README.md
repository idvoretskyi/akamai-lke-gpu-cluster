# OpenTofu Modules

This directory contains reusable OpenTofu modules for deploying GPU-enabled Kubernetes infrastructure with comprehensive monitoring on Linode Kubernetes Engine (LKE).

## Module Overview

### 1. GPU Operator Module (`gpu-operator/`)

Installs the NVIDIA GPU Operator, which provides:
- NVIDIA GPU drivers
- CUDA runtime
- GPU device plugin for Kubernetes
- GPU monitoring (DCGM exporter)
- GPU Feature Discovery

**Key Features:**
- Automatic driver installation
- GPU metrics for Prometheus
- Validation workloads
- Node status monitoring

**Usage:**
```hcl
module "gpu_operator" {
  source = "./modules/gpu-operator"

  namespace                    = "gpu-operator"
  gpu_operator_version         = "v24.9.0"
  install_driver               = true
  enable_dcgm_exporter         = true
  enable_node_status_exporter  = true
}
```

**Outputs:**
- `namespace` - GPU operator namespace
- `gpu_operator_version` - Installed version
- `gpu_operator_status` - Helm release status
- `validation_commands` - Commands to test GPU functionality

### 2. Metrics Server Module (`metrics-server/`)

Installs Kubernetes Metrics Server for resource metrics API:
- Enables `kubectl top` commands
- Provides metrics for Horizontal Pod Autoscaler (HPA)
- High availability with 2 replicas

**Key Features:**
- Resource usage monitoring
- HPA support
- Pod Disruption Budget
- Optimized for Linode environment

**Usage:**
```hcl
module "metrics_server" {
  source = "./modules/metrics-server"

  namespace = "kube-system"
}
```

**Outputs:**
- `release_name` - Helm release name
- `namespace` - Metrics Server namespace
- `version` - Chart version

### 3. Kube Prometheus Stack Module (`kube-prometheus-stack/`)

Installs comprehensive monitoring stack:
- Prometheus (metrics collection and storage)
- Grafana (visualization and dashboards)
- Alertmanager (alert management)
- Node Exporter (hardware metrics)
- Kube State Metrics (Kubernetes object metrics)

**Key Features:**
- Complete observability solution
- GPU metrics integration (via DCGM exporter)
- Persistent storage for metrics and dashboards
- Customizable retention and storage sizes
- Pre-configured for Linode block storage

**Usage:**
```hcl
module "kube_prometheus_stack" {
  source = "./modules/kube-prometheus-stack"

  namespace                = "monitoring"
  grafana_admin_password   = "secure-password"
  prometheus_retention     = "15d"
  prometheus_storage_size  = "50Gi"
  grafana_storage_size     = "10Gi"
  enable_gpu_monitoring    = true
}
```

**Outputs:**
- `namespace` - Monitoring namespace
- `release_name` - Helm release name
- `grafana_service` - Grafana service name
- `prometheus_service` - Prometheus service name
- `alertmanager_service` - Alertmanager service name

## Deployment Workflow

### Step 1: Deploy Base Infrastructure
Deploy the LKE cluster with GPU nodes:
```bash
cd tofu
tofu init
tofu plan
tofu apply
```

### Step 2: Verify GPU Operator
Wait for GPU operator to be ready (~10-15 minutes), then verify:
```bash
kubectl get pods -n gpu-operator
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'
```

### Step 3: Access Monitoring
Access Grafana dashboard:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit: http://localhost:3000 (default: admin/admin)
```

Access Prometheus:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit: http://localhost:9090
```

### Step 4: Check Resource Usage
Use Metrics Server:
```bash
kubectl top nodes
kubectl top pods -A
```

## Configuration Options

### GPU Operator
```hcl
install_gpu_operator  = true
gpu_operator_version  = "v24.9.0"
enable_gpu_monitoring = true
```

### Metrics Server
```hcl
install_metrics_server = true
```

### Monitoring Stack
```hcl
install_monitoring      = true
grafana_admin_password  = "secure-password"
prometheus_retention    = "15d"
prometheus_storage_size = "50Gi"
grafana_storage_size    = "10Gi"
```

## Monitoring GPU Metrics

GPU metrics are exposed via DCGM exporter when GPU monitoring is enabled:

```bash
# Check DCGM exporter pods
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# View GPU metrics in Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then query: dcgm_gpu_utilization
```

## Troubleshooting

### GPU Not Detected
```bash
# Check GPU operator pods
kubectl get pods -n gpu-operator

# Check driver installation
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset

# Verify GPU on nodes
kubectl describe nodes | grep -A 5 Capacity
```

### Monitoring Stack Issues
```bash
# Check monitoring pods
kubectl get pods -n monitoring

# Check persistent volumes
kubectl get pvc -n monitoring

# Check logs
kubectl logs -n monitoring <pod-name>
```

### Metrics Server Issues
```bash
# Check metrics-server pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

# Test metrics API
kubectl top nodes
```

## Module Dependencies

```
linode_lke_cluster
    └─> terraform_data.merge_kubeconfig
        ├─> module.gpu_operator
        ├─> module.metrics_server
        └─> module.kube_prometheus_stack
```

**Important:**
- All modules are optional and can be enabled/disabled independently
- GPU Operator should be ready before GPU workloads
- Monitoring stack integrates with GPU Operator for GPU metrics

## Storage Considerations

Persistent volumes are created for:
- **Prometheus**: 50Gi (configurable)
- **Grafana**: 10Gi (configurable)
- **Alertmanager**: 10Gi (fixed)

Storage class: `linode-block-storage-retain`

## Cost Considerations

Approximate monthly costs (us-ord region):
- **Base cluster**: $1,080-1,440 per GPU node
- **GPU Operator**: Free (software only)
- **Metrics Server**: Free (software only)
- **Monitoring Stack**: Free (software only)
- **Storage**: ~$10-20/month for monitoring volumes

## References

- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Linode Kubernetes Engine](https://www.linode.com/docs/products/compute/kubernetes/)
