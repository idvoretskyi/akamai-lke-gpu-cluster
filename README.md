# Linode GPU Kubernetes Infrastructure

[![CI](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-%3E%3D1.9-844FBA?logo=opentofu&logoColor=white)](https://opentofu.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Linode LKE](https://img.shields.io/badge/Linode-LKE-00A95C?logo=linode&logoColor=white)](https://www.linode.com/products/kubernetes/)

OpenTofu infrastructure code for a cost-effective, GPU-enabled Kubernetes lab
cluster on Linode Kubernetes Engine (LKE), for AI/ML workloads.

## What you get

A two-pool LKE cluster (a small CPU **system** pool + a tainted **GPU** pool),
plus these optional components, each toggled by an `install_*` variable:

| Component | Toggle | Default | Purpose |
|---|---|---|---|
| GPU Operator | `install_gpu_operator` | on | NVIDIA driver + device plugin |
| HAMi | `install_hami` | on | Splits GPUs into shareable vGPU slices |
| Metrics Server | `install_metrics_server` | on | `kubectl top`, HPA |
| kube-prometheus-stack | `install_monitoring` | on | Prometheus + Grafana |
| OpenCost | `install_opencost` | on | Kubernetes cost allocation |
| Kubeflow | `install_kubeflow` | **off** | Full ML platform (heavy, opt-in) |

Autoscaling is intentionally disabled on both pools — fixed node counts keep
costs predictable.

## Prerequisites

- **OpenTofu** >= 1.9
- **linode-cli**, configured (`linode-cli configure`) — the `linode` provider
  auto-resolves its token from `~/.config/linode-cli`, else falls back to the
  `LINODE_TOKEN` environment variable.
- **kubectl**
- **kustomize** and **git** — only if `install_kubeflow = true`

```bash
brew install opentofu kubectl
pip3 install linode-cli && linode-cli configure
```

## Quick Start

```bash
cd tofu
tofu init
tofu apply

# Kubeconfig is auto-merged into ~/.kube/config
kubectl get nodes
kubectl top nodes

kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000 (admin/admin)
```

Deployment time: ~5 min for a bare cluster, ~20–30 min with the full default
stack (GPU Operator + HAMi + monitoring).

## Configuration

Copy `tofu/tofu.tfvars.example` to `tofu/tofu.tfvars` and adjust. The knobs
you're most likely to change:

```hcl
region             = "us-ord"
gpu_node_type      = "g2-gpu-rtx4000a1-s"  # cheapest Linode GPU plan
gpu_node_count     = 1
system_node_type   = "g6-standard-2"       # g6-standard-8 if install_kubeflow
system_node_count  = 1

install_hami            = true
hami_device_split_count = 10   # vGPU slices per physical GPU

install_kubeflow = false       # opt-in, heavy

grafana_admin_password = "admin"
```

See `tofu/variables.tf` for the full list (all variables have descriptions
and sane defaults).

## Node Pools & GPU Scheduling

Two node pools, so the expensive GPU nodes are reserved purely for
GPU-intensive workloads:

| Pool | Default plan | Runs |
|------|--------------|------|
| **system** | `g6-standard-2` (~$24/mo) | Monitoring, Metrics Server, OpenCost, GPU Operator controller |
| **gpu** | `g2-gpu-rtx4000a1-s` (~$380/mo) | GPU workloads only |

Each pool is labelled `nodepool.lke/role` (`system`/`gpu`); system components
are pinned there via `nodeSelector`. When `dedicate_gpu_nodes = true`
(default) the GPU pool is **tainted** `nvidia.com/gpu=present:NoSchedule`, so
your GPU workloads must add a matching toleration and request a GPU:

```yaml
spec:
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  nodeSelector:
    nodepool.lke/role: gpu
  containers:
    - name: cuda
      image: nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
```

With HAMi enabled (default), request `nvidia.com/gpumem` for an explicit
vGPU memory slice; without it, requests get `hami_default_gpu_memory` MB
(default 8000) rather than the whole card. Set `dedicate_gpu_nodes = false`
to remove the taint.

## Validating the Cluster

Three runnable examples, in increasing order of what they cover:

- [`examples/gpu-validation/`](examples/gpu-validation/) — bare CUDA pod,
  proves the GPU Operator works. `make -C examples/gpu-validation apply wait logs`
- [`examples/hami-validation/`](examples/hami-validation/) — two pods sharing
  one physical GPU via HAMi vGPU slices. `make -C examples/hami-validation apply wait logs clean`
- [`examples/roboflow-pipeline/`](examples/roboflow-pipeline/) — a real,
  keyless object-detection workload through Kubeflow Pipelines, proving
  HAMi's admission webhook intercepts pods it wasn't given an explicit
  scheduler hint for (requires `install_kubeflow = true`)

For platform iteration that shouldn't require re-running `tofu apply`, or a
more elaborate CV MLOps lab, see
[`kubeflow-cv-lab`](https://github.com/idvoretskyi/kubeflow-cv-lab).

## Accessing Services

```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# OpenCost
kubectl port-forward -n opencost svc/opencost 9090:9090

# GPU capacity / usage
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'
kubectl top nodes && kubectl top pods -A
```

## Cost

| Resource | Cost |
|---|---|
| GPU node (`g2-gpu-rtx4000a1-s`) | ~$0.52/hr (~$380/month) |
| System node (`g6-standard-2`) | ~$24/month |
| Monitoring storage (~20Gi) | ~$2/month |

**~$406/month** running. Approximate — check
[Linode Pricing](https://www.linode.com/pricing/) for current rates.

```bash
cd tofu && tofu destroy   # stop paying
cd tofu && tofu apply     # bring it back
```

## Security

- The Linode API token is read from `~/.config/linode-cli` (if configured)
  or the `LINODE_TOKEN` environment variable — never committed or stored in
  state (see `tofu/locals.tf`).
- Kubeconfig is excluded from git and auto-merged into `~/.kube/config`.
- `allowed_kubectl_ips` and `allowed_monitoring_ips` default to `0.0.0.0/0`
  (open) — restrict to your IP if you expose the cluster:

  ```hcl
  allowed_kubectl_ips    = ["YOUR_IP/32"]
  allowed_monitoring_ips = ["YOUR_IP/32"]
  ```

- Intra-cluster firewall rules allow the control plane to reach kubelet
  (`:10250`) and admission webhooks (`:9443`) — required for Trainer v2 /
  JobSet to work; `node_cidrs`/`pod_cidrs` default to the standard Linode LKE
  ranges and shouldn't need changes.
- Grafana admin password is configurable (`grafana_admin_password`, sensitive).

## Repository Layout

```text
.
├── examples/              # Runnable validation examples (see above)
└── tofu/                  # OpenTofu infrastructure code
    ├── cluster.tf          # LKE cluster resource
    ├── firewall.tf         # Linode firewall resource
    ├── kubeconfig.tf       # Kubeconfig merge resource
    ├── locals.tf           # Shared locals
    ├── modules.tf          # Module calls
    ├── checks.tf           # Advisory check blocks
    ├── variables.tf        # Configuration variables
    ├── outputs.tf          # Output values
    ├── tofu.tfvars.example # Configuration template
    ├── scripts/            # Helper scripts (kubeconfig merge)
    └── modules/            # gpu-operator, hami, kubeflow, metrics-server,
                             # kube-prometheus-stack, opencost — see
                             # tofu/modules/README.md
```

## Contributing

Contributions are welcome — open an issue or pull request.

## License

MIT — see [LICENSE](LICENSE).

## Author

Ihor Dvoretskyi ([@idvoretskyi](https://github.com/idvoretskyi))
