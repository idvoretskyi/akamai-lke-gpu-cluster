# Linode GPU Kubernetes Infrastructure

[![CI](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-%3E%3D1.9-844FBA?logo=opentofu&logoColor=white)](https://opentofu.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Linode LKE](https://img.shields.io/badge/Linode-LKE-00A95C?logo=linode&logoColor=white)](https://www.linode.com/products/kubernetes/)

OpenTofu infrastructure code for deploying cost-effective, GPU-enabled Kubernetes lab clusters on Linode Kubernetes Engine (LKE) for AI/ML workloads.

## Overview

This repository provides automated infrastructure deployment for GPU-accelerated Kubernetes clusters with comprehensive monitoring, designed to serve as a foundation for AI/ML platforms and workloads.

**Key Features:**

- **GPU Compute**: NVIDIA RTX 4000 Ada GPU nodes with automated driver installation
- **Dedicated System Pool**: A small, cheap CPU node pool runs the system/monitoring stack so the GPU nodes are reserved purely for GPU-intensive workloads
- **GPU Operator**: NVIDIA GPU Operator for automated GPU management and monitoring
- **HAMi GPU Virtualization**: Splits physical GPUs into shareable vGPU slices so multiple pods can run on one GPU (enabled by default — lab setup)
- **Local LLM Serving**: Ollama on the GPU node (`install_ollama`, on by default) with native and OpenAI-compatible APIs
- **Coding-agent backend**: opt-in vLLM (`install_vllm`) or llama.cpp (`install_llamacpp`) serving one model with tool calling and an API key, ready for opencode
- **Metrics API**: Kubernetes Metrics Server for resource monitoring and HPA
- **Monitoring Stack**: Complete observability with Prometheus, Grafana, node-exporter and kube-state-metrics
- **Cost Monitoring**: OpenCost for real-time Kubernetes cost allocation
- **Kubeflow (optional)**: Full Kubeflow Platform installable in-repo (`install_kubeflow = true`) via `modules/kubeflow`
- **ML Platform Ready**: Infrastructure foundation for Kubeflow, Ray, MLflow, and custom ML workloads (see [kubeflow-cv-lab](https://github.com/idvoretskyi/kubeflow-cv-lab))
- **Fixed Node Counts**: Autoscaling disabled — predictable, bounded costs with no surprise scale-up events
- **Security**: Configurable firewall rules and network policies
- **Automation**: One-command deployment and management

Designed as infrastructure foundation for AI/ML platforms like Kubeflow, Ray, MLflow, and custom ML workloads.

## Quick Start

```bash
# Configure Linode API token — skip this if `linode-cli configure` is
# already set up (the provider auto-resolves it from ~/.config/linode-cli;
# see Prerequisites below)
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
- With Ollama and the default models: add ~20-40 minutes for ~49 GB of downloads

## Prerequisites

- **OpenTofu** >= 1.9 - Infrastructure as code tool
- **linode-cli** - Linode API client (configured with token). The `linode`
  provider auto-resolves its token from the default user in
  `~/.config/linode-cli` if present (see `tofu/providers.tf` and
  `tofu/locals.tf`), else falls back to its own `LINODE_TOKEN` environment
  variable lookup — so `linode-cli configure` alone is enough; no separate
  `export LINODE_TOKEN` needed (the linode-cli config takes priority over
  `LINODE_TOKEN` if both are present).
- **kubectl** - Kubernetes command-line tool
- **kustomize** and **git** - only required if `install_kubeflow = true` (the `kubeflow` module shells out to `kustomize build | kubectl apply`)

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
│   ├── gpu-validation/    # Kubeflow-free nvidia-smi GPU smoke test
│   ├── hami-validation/   # Two Pods sharing one GPU via HAMi vGPU slices
│   ├── ollama/            # Chat with the cluster's Ollama over port-forward
│   ├── vllm-opencode/     # vLLM checks (tool calling) and an opencode config
│   └── roboflow-pipeline/ # Keyless Roboflow RF-DETR workload on Kubeflow Pipelines
└── tofu/                  # OpenTofu infrastructure code
    ├── versions.tf        # Required providers and OpenTofu version (>= 1.9)
    ├── providers.tf       # Provider configurations
    ├── locals.tf          # Shared locals (prefix, token resolution, node labels/taints, pools, k8s auth)
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
        ├── hami/               # HAMi GPU virtualization/sharing
        ├── kubeflow/           # Full Kubeflow Platform (opt-in, kustomize-based)
        ├── metrics-server/     # Kubernetes Metrics Server
        ├── kube-prometheus-stack/ # Monitoring stack
        ├── llamacpp/           # llama.cpp llama-server for GGUF models (opt-in)
        ├── ollama/             # Ollama LLM server on the GPU pool
        ├── opencost/           # Kubernetes cost monitoring
        └── vllm/               # vLLM OpenAI-compatible server (opt-in)
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
region             = "de-fra-2"
kubernetes_version = "1.36"
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

# HAMi GPU virtualization — lab default: enabled
install_hami            = true
hami_device_split_count = 10
hami_default_gpu_memory = 8000  # MB given to unslotted nvidia.com/gpu requests

# Kubeflow — opt-in, heavy
install_kubeflow = false

# Monitoring (Prometheus + Grafana)
install_monitoring      = true
grafana_admin_password  = "admin"
prometheus_retention    = "7d"
prometheus_storage_size = "15Gi"
grafana_storage_size    = "5Gi"

install_opencost = true

# Ollama — local LLM serving, takes the whole GPU
install_ollama      = true
ollama_models       = ["gpt-oss:20b", "gemma4:12b", "qwen3.5:9b", "qwen3.8:27b"]
ollama_storage_size = "80Gi"
```

## Node Pools & Scheduling

The cluster runs **two node pools** so the expensive GPU nodes are reserved
purely for GPU-intensive workloads:

| Pool | Default plan | Purpose |
|------|--------------|---------|
| **system** | `g6-standard-2` (2 vCPU / 4 GB, ~$24/mo) | Monitoring stack (Prometheus, Grafana, kube-state-metrics), Metrics Server, OpenCost, and the GPU Operator controller |
| **gpu** | `g2-gpu-rtx4000a1-s` | GPU-intensive workloads only (Ollama by default) |

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

This repo can provision the GPU substrate only (GPU Operator + HAMi), or the
full stack including Kubeflow — both are installed in-repo via
`install_gpu_operator`, `install_hami`, and `install_kubeflow` (see
`tofu/modules/`). For platform updates that shouldn't require re-running
`tofu apply`, or a more elaborate CV MLOps lab, see
[`kubeflow-cv-lab`](https://github.com/idvoretskyi/kubeflow-cv-lab).

**GPU scheduling contract** (applies to any GPU workload on this cluster):

- Request a GPU: `nvidia.com/gpu` resource limit = 1 (add `nvidia.com/gpumem`
  for an explicit HAMi vGPU slice size; without it, requests get
  `hami_default_gpu_memory` MB by default — see `modules/hami/README.md` —
  not the whole card)
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

**HAMi GPU virtualization validation** — [`examples/hami-validation/`](examples/hami-validation/)
proves two Pods can share one physical GPU via vGPU memory slices (requires
`install_hami = true`):

```bash
make -C examples/hami-validation apply wait logs clean
```

**Roboflow RF-DETR on Kubeflow Pipelines** — [`examples/roboflow-pipeline/`](examples/roboflow-pipeline/)
runs a real, keyless object-detection workload through Kubeflow Pipelines,
validating that HAMi's admission webhook correctly intercepts GPU pods
created by Argo Workflows (no explicit scheduler hint needed, unlike the two
examples above). Requires `install_kubeflow = true` and `install_hami = true`:

```bash
cd examples/roboflow-pipeline
make venv compile
# In one terminal: make port-forward
# In another:      make run
```

## Serving LLMs with Ollama

With `install_ollama = true` (the default), the GPU node runs an
[Ollama](https://ollama.com/) server that holds the whole GPU. It pulls
`ollama_models` onto an 80 GB volume on first start; the first `tofu apply`
therefore waits for the downloads (~49 GB for the defaults).

| Model | Download | Why |
|---|---|---|
| `gpt-oss:20b` | 14 GB | OpenAI's open-weight reasoning model; closest to frontier behaviour that fits 20 GB |
| `gemma4:12b` | 7.7 GB | Newest Gemma; vision, 128K context |
| `qwen3.5:9b` | 6.6 GB | Newest Qwen with a small size; vision |
| `qwen3.8:27b` | 18 GB | Newest Qwen; tight fit, 8K context |

Frontier-scale open models (Kimi K2, DeepSeek V3, GLM-5) are hundreds of GB
and don't fit a single 20 GB GPU.

Ollama has no authentication, so it stays ClusterIP-only. Reach it from any
machine with cluster access:

```bash
kubectl port-forward -n ollama service/ollama 11434:11434
curl http://localhost:11434/api/tags
# OpenAI-compatible clients: base URL http://localhost:11434/v1, any API key
```

See [`examples/ollama/`](examples/ollama/) for chat and benchmark targets, and
[`tofu/modules/ollama/README.md`](tofu/modules/ollama/README.md) for tuning.
While Ollama runs, other GPU workloads can't schedule; set
`install_ollama = false` to free the GPU.

## Local LLM serving for opencode

For agentic coding (long repeated system prompts, tool calls on every turn,
32K to 64K contexts) the cluster can run [vLLM](https://docs.vllm.ai)
instead of Ollama, as an OpenAI-compatible backend for
[opencode](https://opencode.ai):

```hcl
install_ollama     = false          # one GPU server at a time
install_vllm       = true
vllm_model_profile = "gpt-oss-20b"  # or "qwen3-coder-30b"
```

| Preset | Model | Context | Notes |
|---|---|---|---|
| `gpt-oss-20b` (default) | `openai/gpt-oss-20b`, MXFP4 | 64K | Fastest; reasoning model with native tool calling |
| `qwen3-coder-30b` | `QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ` | 32K | Coding-specialised MoE |

Both are MoE models with about 3B active parameters, which matters on this
GPU's ~360 GB/s memory bandwidth: expect roughly 50 to 90 tokens per second.
Dense models such as Qwen3.8-27B do not fit vLLM on 20 GB; run them as GGUF
with the optional llama.cpp module (`install_llamacpp = true`).

The Service is ClusterIP only and requires an API key (generated unless you
set `vllm_api_key`):

```bash
make -C examples/vllm-opencode port-forward   # localhost:8000
export VLLM_API_KEY="$(tofu -chdir=tofu output -raw vllm_api_key)"
make -C examples/vllm-opencode health tool-call
opencode -m lke-vllm/gpt-oss-20b              # with examples/vllm-opencode/opencode.json
```

The model cache uses the `linode-block-storage` class, so `tofu destroy`
deletes it and nothing stays billed; the weights download again (about 14 to
17 GB) after each recreate. See
[`examples/vllm-opencode/`](examples/vllm-opencode/) and
[`tofu/modules/vllm/README.md`](tofu/modules/vllm/README.md).

## Cluster Specifications

| Component | Specification |
|-----------|--------------|
| Platform | Linode Kubernetes Engine (LKE) |
| Region | Frankfurt 2, DE (de-fra-2) |
| Kubernetes | v1.36 (configurable) |
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
| Ollama model storage (80Gi, `install_ollama`) | ~$8/month |
| vLLM model cache (50Gi, `install_vllm`, deleted on destroy) | ~$5/month |

**Estimated running cost:** ~$414/month. Destroy the cluster when not in use to stop paying.

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

- API token resolved from the default user in `~/.config/linode-cli` if present, else the `LINODE_TOKEN` environment variable (linode-cli config wins when both exist)
- Kubeconfig excluded from git tracking (auto-merged to ~/.kube/config)
- Configurable firewall rule for kubectl access (monitoring UIs are ClusterIP / port-forward only)
- Intra-cluster firewall rules allow the Kubernetes API server (Linode control-plane) to reach kubelet (`:10250`) and admission webhooks (`:9443`) — required for Trainer v2 / JobSet to work
- Support for Kubernetes RBAC and Network Policies
- Grafana admin password (configurable, sensitive)

`allowed_kubectl_ips` defaults to `0.0.0.0/0`. Restrict to your IP if you expose the cluster:

```hcl
allowed_kubectl_ips = ["YOUR_IP/32"]
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
# Edit tofu/tofu.tfvars: kubernetes_version = "1.36"
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

**Access Ollama:**

```bash
kubectl port-forward -n ollama svc/ollama 11434:11434
# API: http://localhost:11434 — OpenAI-compatible: http://localhost:11434/v1
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
- Node Exporter (hardware and OS metrics)
- Kube State Metrics (Kubernetes object metrics)
- DCGM Exporter (GPU metrics integration)
- OpenCost (Kubernetes cost monitoring and allocation)

### GPU Support

- NVIDIA GPU Operator (automated driver management)
- GPU device plugin (resource scheduling) — provided by HAMi when enabled, else the stock NVIDIA plugin
- HAMi GPU virtualization — splits physical GPUs into vGPU slices (memory/core sharing across pods)
- GPU monitoring with DCGM exporter
- GPU metrics integration with Prometheus
- Support for CUDA workloads

### LLM Serving

- Ollama on the GPU pool (`install_ollama = true`) — native and OpenAI-compatible APIs over `kubectl port-forward`
- Models preloaded onto a persistent volume; flash attention and a quantized KV cache keep ~27B Q4 models on a 20 GB GPU

### ML Platform (optional)

- Full Kubeflow Platform (`install_kubeflow = true`) — Pipelines, Katib, Notebooks, KServe, Trainer, Spark Operator, Central Dashboard
- Installed via `kustomize build | kubectl apply` (see `modules/kubeflow/README.md`)

## Use Cases

This infrastructure is designed for:

- **ML Platform Deployment**: Foundation for Kubeflow, MLflow, Ray, etc.
- **AI Model Training**: Distributed training with GPU acceleration
- **AI Model Serving**: Inference workloads with GPU support, including local LLMs via Ollama
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
- [Ollama Documentation](https://docs.ollama.com/)

## Region and GPU availability

RTX 4000 Ada plans (`g2-gpu-*`) are not offered in London (`gb-lon`). The default region is `de-fra-2` (Frankfurt 2), a balanced choice for UK and Ukraine access; `fr-par` (Paris) is the other EU region with these plans. Check current availability with:

```bash
linode-cli regions list-avail --json --all-rows \
  | jq -r '.[] | select(.plan|startswith("g2-gpu")) | select(.available) | .region' | sort -u
```

## Migration notes

- `opencost_chart_version` was renamed to `opencost_version`.
- `allowed_monitoring_ips` was removed (the monitoring firewall rule was unused; all UIs are port-forward only).
- New optional variables: `metrics_server_version`, `kube_prometheus_stack_version`.
- Helm releases now use `atomic = true` and `cleanup_on_fail = true`: a failed install/upgrade is rolled back automatically, so inspect pod logs during the timeout window.
- `install_ollama` defaults to `true`: the next apply adds an Ollama pod that takes the whole GPU and an 80 GB volume (~$8/month). Set `install_ollama = false` to opt out.
- Changing `region` replaces the cluster, and the kubernetes/helm providers cannot plan across a cluster replacement. Run `tofu destroy` on the old cluster, then `tofu apply`.

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
