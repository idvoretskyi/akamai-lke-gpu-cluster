# Linode GPU Kubernetes Infrastructure

[![CI](https://github.com/idvoretskyi/linode-gpu-k8s/actions/workflows/ci.yml/badge.svg)](https://github.com/idvoretskyi/linode-gpu-k8s/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-%3E%3D1.9-844FBA?logo=opentofu&logoColor=white)](https://opentofu.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Linode LKE](https://img.shields.io/badge/Linode-LKE-00A95C?logo=linode&logoColor=white)](https://www.linode.com/products/kubernetes/)

OpenTofu infrastructure code for deploying cost-effective, GPU-enabled Kubernetes lab clusters on Linode Kubernetes Engine (LKE) for AI/ML workloads.

## Overview

This repository provides automated infrastructure deployment for GPU-accelerated Kubernetes clusters with comprehensive monitoring, designed to serve as a foundation for AI/ML platforms and workloads.

**Key Features:**

- **GPU Compute**: NVIDIA RTX 4000 Ada GPU nodes with automated driver installation
- **Dedicated System Pool**: A small, cheap CPU node pool runs the system/monitoring stack so the GPU nodes are reserved purely for GPU-intensive workloads
- **GPU Operator**: NVIDIA GPU Operator for automated GPU management and monitoring
- **Metrics API**: Kubernetes Metrics Server for resource monitoring and HPA
- **Monitoring Stack**: Complete observability with Prometheus, Grafana, and Alertmanager
- **Cost Monitoring**: OpenCost for real-time Kubernetes cost allocation
- **ML Platform Ready**: Infrastructure foundation for Kubeflow, Ray, MLflow, and custom ML workloads (see [kubeflow-cv-lab](https://github.com/idvoretskyi/kubeflow-cv-lab))
- **Fixed Node Counts**: Autoscaling disabled — predictable, bounded costs with no surprise scale-up events
- **Security**: Configurable firewall rules and network policies
- **Automation**: One-command deployment and management

Designed as infrastructure foundation for AI/ML platforms like Kubeflow, Ray, MLflow, and custom ML workloads.

## Quick Start

```bash
# Configure Linode API token (paste your Personal Access Token)
export LINODE_TOKEN="YOUR_PERSONAL_ACCESS_TOKEN"

# Initialize and deploy
cd tofu
tofu init
tofu plan
tofu apply

# Access cluster (kubeconfig automatically merged to ~/.kube/config)
kubectl get nodes
kubectl top nodes

# Access Grafana dashboard
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Then visit: http://localhost:3000 (admin/admin)
```

**Deployment time:**

- Basic cluster: ~5 minutes
- With GPU operator: ~15-20 minutes
- With full monitoring stack: ~20-30 minutes

## Prerequisites

- **OpenTofu** >= 1.9 - Infrastructure as code tool
- **linode-cli** - Linode API client (configured with token)
- **kubectl** - Kubernetes command-line tool

### macOS Installation

```bash
brew install opentofu kubectl
pip3 install linode-cli
linode-cli configure
```

## Project Structure

```text
.
├── README.md              # This file
├── LICENSE                # MIT License
├── .github/               # GitHub Actions CI and Dependabot config
├── examples/              # Runnable examples
│   └── gpu-validation/    # Kubeflow-free nvidia-smi GPU smoke test
└── tofu/                  # OpenTofu infrastructure code
    ├── versions.tf        # Required providers and OpenTofu version (>= 1.9)
    ├── providers.tf       # Provider configurations
    ├── locals.tf          # Shared locals (cluster prefix, username)
    ├── cluster.tf         # LKE cluster resource
    ├── firewall.tf        # Linode firewall resource
    ├── kubeconfig.tf      # Kubeconfig merge resource
    ├── modules.tf         # Module calls
    ├── checks.tf          # Advisory check blocks
    ├── variables.tf       # Configuration variables
    ├── outputs.tf         # Output values
    ├── tofu.tfvars.example # Configuration template
    ├── scripts/           # Helper scripts (kubeconfig merge)
    └── modules/           # Reusable modules
        ├── gpu-operator/       # NVIDIA GPU Operator
        ├── metrics-server/     # Kubernetes Metrics Server
        ├── kube-prometheus-stack/ # Monitoring stack
        └── opencost/           # Kubernetes cost monitoring
```

## Workflow

Common OpenTofu actions:

```bash
# From repo root
cd tofu

# Initialize providers and modules
tofu init

# Review and apply changes
tofu plan && tofu apply

# Format and validate configuration
tofu fmt -recursive && tofu validate

# Destroy infrastructure when no longer needed
tofu destroy
```

For detailed module documentation, see `tofu/modules/README.md`.

## Configuration

Copy `tofu/tofu.tfvars.example` to `tofu/tofu.tfvars` and adjust as needed:

```hcl
region             = "us-ord"
kubernetes_version = "1.35"
gpu_node_type      = "g2-gpu-rtx4000a1-s"  # RTX 4000 Ada (~$0.52/hr)
gpu_node_count     = 1

# System pool — 4 GB fits the monitoring stack and GPU Operator controller
system_node_type  = "g6-standard-2"  # 2 vCPU / 4 GB (~$24/month)
system_node_count = 1
dedicate_gpu_nodes = true

ha_control_plane = false

install_gpu_operator   = true
enable_gpu_monitoring  = true
install_metrics_server = true

# Monitoring (Prometheus + Grafana)
install_monitoring      = true
grafana_admin_password  = "admin"
prometheus_retention    = "7d"
prometheus_storage_size = "15Gi"
grafana_storage_size    = "5Gi"

install_opencost = true
```

## Node Pools & Scheduling

The cluster runs **two node pools** so the expensive GPU nodes are reserved
purely for GPU-intensive workloads:

| Pool | Default plan | Purpose |
|------|--------------|---------|
| **system** | `g6-standard-2` (2 vCPU / 4 GB, ~$24/mo) | Monitoring stack (Prometheus, Grafana, kube-state-metrics), Metrics Server, OpenCost, and the GPU Operator controller |
| **gpu** | `g2-gpu-rtx4000a1-s` | GPU-intensive workloads only |

How it works:

- Each pool is labelled with `nodepool.lke/role` (`system` / `gpu`).
- System components are pinned to the system pool via `nodeSelector`.
- When `dedicate_gpu_nodes = true` (the default) the GPU pool is **tainted** with
  `nvidia.com/gpu=present:NoSchedule`. Only pods that tolerate this taint land
  on GPU nodes. The GPU Operator's GPU operands (driver, toolkit, device-plugin,
  DCGM, GFD, NFD worker) tolerate it by default, and the `node-exporter`
  DaemonSet keeps running cluster-wide so GPU node metrics are still scraped.

Because GPU nodes are tainted, **your GPU workloads must add a matching
toleration** (and request a GPU):

```yaml
spec:
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  nodeSelector:
    nodepool.lke/role: gpu        # optional: force onto the GPU pool
  containers:
    - name: cuda
      image: nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
```

To disable the taint and allow general workloads back onto GPU nodes, set
`dedicate_gpu_nodes = false`.

## Running ML Platforms on This Cluster

This repo provisions the cluster and installs the NVIDIA GPU operator. ML
platforms (Kubeflow, MLflow, KServe, etc.) are managed separately so that
platform updates don't require re-running `tofu apply`.

**Kubeflow 26.03** — see
[`kubeflow-cv-lab`](https://github.com/idvoretskyi/kubeflow-cv-lab) for the
portable installer and an end-to-end CV MLOps lab:

```bash
# After tofu apply (cluster + GPU operator are up):
git clone https://github.com/idvoretskyi/kubeflow-cv-lab
cd kubeflow-cv-lab
cp platform/config.env.example platform/config.env   # LKE defaults work as-is
make platform-install
```

**GPU scheduling contract** (applies to any GPU workload on this cluster):

- Request a GPU: `nvidia.com/gpu` resource limit = 1
- Tolerate the taint: `nvidia.com/gpu=present:NoSchedule`
- Pin to the GPU pool: node selector `nodepool.lke/role=gpu`

**GPU substrate validation** — [`examples/gpu-validation/`](examples/gpu-validation/)
confirms the GPU substrate is working right after `tofu apply`, before installing any
ML platform:

```bash
make -C examples/gpu-validation apply wait logs
# Schedules a bare CUDA Pod, runs nvidia-smi, prints GPU info.
# No Kubeflow required — only the GPU Operator must be running.
```

For the **Trainer v2 GPU example** (requires Kubeflow), see
[`examples/pytorch-training/`](https://github.com/idvoretskyi/kubeflow-cv-lab/tree/main/examples/pytorch-training)
in `kubeflow-cv-lab`.

## Cluster Specifications

| Component | Specification |
|-----------|--------------|
| Platform | Linode Kubernetes Engine (LKE) |
| Region | Chicago, IL (us-ord) |
| Kubernetes | v1.35 (configurable) |
| GPU | NVIDIA RTX 4000 Ada (1 per node) |
| CPU | 4 vCPU per node |
| Memory | 16 GB per node |
| Storage | 512 GB SSD per node |
| GPU nodes | 1 (fixed, autoscaling disabled) |
| System pool | `g6-standard-2` (2 vCPU / 4 GB), 1 node (fixed) |

## Cost Estimation

| Resource | Cost |
|---|---|
| GPU node (`g2-gpu-rtx4000a1-s`) | ~$0.52/hr (~$380/month) |
| System node (`g6-standard-2`) | ~$24/month |
| Monitoring storage (~20Gi) | ~$2/month |

**Estimated running cost:** ~$406/month. Destroy the cluster when not in use to stop paying.

Costs are approximate. Check [Linode Pricing](https://www.linode.com/pricing/) for current rates.

### Cost management

To stop paying for compute, destroy the cluster:

```bash
cd tofu && tofu destroy
```

To bring it back up:

```bash
cd tofu && tofu apply
```

## Security

- API token read from the `LINODE_TOKEN` environment variable
- Kubeconfig excluded from git tracking (auto-merged to ~/.kube/config)
- Configurable firewall rules for kubectl and monitoring access
- Intra-cluster firewall rules allow the Kubernetes API server (Linode control-plane) to reach kubelet (`:10250`) and admission webhooks (`:9443`) — required for Trainer v2 / JobSet to work
- Support for Kubernetes RBAC and Network Policies
- Grafana admin password (configurable, sensitive)

`allowed_kubectl_ips` and `allowed_monitoring_ips` default to `0.0.0.0/0`. Restrict to your IP if you expose the cluster:

```hcl
allowed_kubectl_ips    = ["YOUR_IP/32"]
allowed_monitoring_ips = ["YOUR_IP/32"]
```

The intra-cluster CIDR variables default to Linode LKE ranges and should not need changes:

```hcl
node_cidrs = ["192.168.128.0/17"]   # Linode node + control-plane private IPs
pod_cidrs  = ["10.2.0.0/16"]        # LKE pod CIDR
```

## Cluster Management

**Scale nodes:**

```bash
# Edit tofu/tofu.tfvars: gpu_node_count = 2
cd tofu && tofu apply
```

**Update Kubernetes version:**

```bash
# Edit tofu/tofu.tfvars: kubernetes_version = "1.35"
cd tofu && tofu apply
```

**Access Grafana:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit: http://localhost:3000 (default: admin/admin)
```

**Access Prometheus:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit: http://localhost:9090
```

**Access OpenCost:**

```bash
kubectl port-forward -n opencost svc/opencost 9090:9090
# Visit: http://localhost:9090
```

**Check GPU availability:**

```bash
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'
kubectl get pods -n gpu-operator
```

**Check resource usage:**

```bash
kubectl top nodes
kubectl top pods -A
```

**Destroy cluster:**

```bash
cd tofu && tofu destroy
```

## Features

### Infrastructure

- LKE cluster with GPU nodes (NVIDIA RTX 4000 Ada)
- Dedicated CPU system pool keeping system/monitoring workloads off GPU nodes
- GPU nodes tainted for exclusive GPU-workload scheduling (toggleable)
- NVIDIA GPU Operator with automated driver installation
- Optional HA control plane (disabled by default)
- Fixed node counts (autoscaling disabled) — predictable, bounded costs
- Firewall rules and network policies
- OpenTofu-based automation
- Kubeconfig auto-merge to ~/.kube/config (no local files)

### Observability

- Kubernetes Metrics Server (resource metrics API)
- Prometheus (metrics collection and storage)
- Grafana (visualization and dashboards)
- Alertmanager (alert management)
- Node Exporter (hardware and OS metrics)
- Kube State Metrics (Kubernetes object metrics)
- DCGM Exporter (GPU metrics integration)
- OpenCost (Kubernetes cost monitoring and allocation)

### GPU Support

- NVIDIA GPU Operator (automated driver management)
- GPU device plugin (resource scheduling)
- GPU monitoring with DCGM exporter
- GPU metrics integration with Prometheus
- Support for CUDA workloads

## Use Cases

This infrastructure is designed for:

- **ML Platform Deployment**: Foundation for Kubeflow, MLflow, Ray, etc.
- **AI Model Training**: Distributed training with GPU acceleration
- **AI Model Serving**: Inference workloads with GPU support
- **Data Science Workflows**: Jupyter notebooks with GPU access
- **Custom ML Applications**: Any containerized AI/ML workload
- **Development & Testing**: GPU-enabled development environments

## Resources

- [Linode Kubernetes Engine Documentation](https://www.linode.com/docs/products/compute/kubernetes/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [OpenCost Documentation](https://www.opencost.io/docs/)

## Support

For issues and questions:

- Review the troubleshooting commands in the sections above
- Check `tofu/modules/README.md` for module-specific troubleshooting
- Visit [Linode Community Forums](https://www.linode.com/community/)
- Consult [Kubernetes documentation](https://kubernetes.io/docs/)
- Open an issue on GitHub

## Contributing

Contributions are welcome! Open an issue or pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Ihor Dvoretskyi ([@idvoretskyi](https://github.com/idvoretskyi))

## Acknowledgments

- [Akamai/Linode](https://www.linode.com/) for the cloud platform
- [OpenTofu](https://opentofu.org/) community for infrastructure-as-code tooling
- [Kubernetes](https://kubernetes.io/) community
- [NVIDIA](https://www.nvidia.com/) for GPU support and documentation
- [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/) communities
