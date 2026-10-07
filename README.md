# Akamai LKE GPU Lab

[![CI](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-%3E%3D1.9-844FBA?logo=opentofu&logoColor=white)](https://opentofu.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)

A reference lab: one Akamai (Linode) LKE cluster with the cheapest
single-GPU plan on the market (NVIDIA RTX 4000 Ada, 20 GB), running useful
open source software from the CNCF and Linux Foundation, with
[Ollama](https://ollama.com/) as the key tool. Everything is OpenTofu; destroy
it when you are done.

## What you get

| Component | Project | Where | Default |
|---|---|---|---|
| GPU Operator | NVIDIA | system pool (operands on GPU) | on |
| [HAMi](https://github.com/Project-HAMi/HAMi) | CNCF sandbox | GPU slicing | on |
| [Ollama](https://ollama.com/) | MIT | GPU pool, 16 GB slice | on |
| [Argo Workflows](https://argoproj.github.io/workflows/) | CNCF graduated | system pool | on |
| Prometheus + Grafana (kube-prometheus-stack) | CNCF | system pool | on |
| [OpenCost](https://www.opencost.io/) | CNCF | system pool | on |
| Metrics Server | Kubernetes SIG | system pool | on |
| [Open WebUI](https://github.com/open-webui/open-webui) | MIT | system pool | off |

The cluster has two fixed-size pools (autoscaling is off, so costs are
predictable): a small CPU **system** pool and the **GPU** pool.

## The GPU story

One 20 GB card is shared through HAMi vGPU slices:

```text
RTX 4000 Ada, 20 GB
├── Ollama           16000 MiB   ollama_gpu_memory_mib
└── any GPU pod       4000 MiB   hami_default_gpu_memory (e.g. an Argo Workflow step)
```

Ollama serves the models; a plain `nvidia.com/gpu: 1` request from any other
pod gets the 4000 MiB default slice and schedules next to it. HAMi's admission
webhook sets the scheduler automatically; nothing extra is needed in the pod.
Set `install_hami = false` to hand the whole card to Ollama (then other GPU
pods will not schedule), or raise `ollama_gpu_memory_mib` to 20000 for the
larger models.

## Quick start

```bash
# Auth: `linode-cli configure`, or export LINODE_TOKEN
cp tofu/tofu.tfvars.example tofu/tofu.tfvars   # edit as needed
cd tofu
tofu init
tofu apply -var-file=tofu.tfvars

kubectl get nodes            # kubeconfig is merged into ~/.kube/config
```

`tofu.tfvars` is **not** loaded automatically; pass `-var-file=tofu.tfvars`
(or name the file `tofu.auto.tfvars`, which is loaded without the flag).

Timing: ~15-30 minutes for the cluster and charts, plus ~20-40 minutes on the
first apply for the ~29 GB of Ollama model downloads.

Prerequisites: [OpenTofu](https://opentofu.org) >= 1.9, `kubectl`, and
`linode-cli` (the provider reads its token from `~/.config/linode-cli`, else
`LINODE_TOKEN`). `kubectl` is also used by `tofu apply` to merge the
kubeconfig and restart the HAMi scheduler.

## Try it

```bash
make -C examples/gpu-validation apply wait logs   # nvidia-smi in a CUDA pod
make -C examples/hami-validation apply wait logs  # two pods sharing the card
make -C examples/argo-gpu-job submit wait logs    # GPU step in an Argo Workflow

make -C examples/ollama port-forward              # terminal 1
make -C examples/ollama models chat               # terminal 2
```

Web UIs are ClusterIP only; reach them with `kubectl port-forward`:

| UI | Command | URL |
|---|---|---|
| Grafana (admin/admin by default) | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` | <http://localhost:3000> |
| Prometheus | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | <http://localhost:9090> |
| OpenCost | `kubectl port-forward -n opencost svc/opencost 9091:9090` | <http://localhost:9091> |
| Argo Workflows | `kubectl port-forward -n argo svc/argo-workflows-server 2746:2746` | <http://localhost:2746> |
| Open WebUI | `kubectl port-forward -n open-webui svc/open-webui 8080:80` | <http://localhost:8080> |
| Ollama API | `kubectl port-forward -n ollama svc/ollama 11434:11434` | <http://localhost:11434> |

Every `tofu apply` also prints `*_validation_commands` outputs per component.

## Scheduling

- Pools are labelled `nodepool.lke/role=system|gpu`; system components are
  pinned to the system pool.
- With `dedicate_gpu_nodes = true` (default) the GPU pool carries the taint
  `nvidia.com/gpu=present:NoSchedule`. GPU pods need this toleration and an
  `nvidia.com/gpu` limit:

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
containers:
  - name: cuda
    image: nvidia/cuda:12.4.1-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: "1"
```

- LKE GPU nodes already ship the NVIDIA driver, container toolkit and an
  `nvidia` containerd runtime, so the GPU Operator installs neither.

## Configuration

All settings live in `tofu/tofu.tfvars.example`, which is the source of truth
for variable names and defaults. The ones you are most likely to change:

| Variable | Default | Notes |
|---|---|---|
| `region` | `de-fra-2` | must offer the RTX 4000 Ada plan |
| `gpu_node_type` | `g2-gpu-rtx4000a1-s` | |
| `system_node_type` | `g6-standard-2` | 4 GB; must differ from `gpu_node_type` |
| `install_ollama`, `ollama_models` | on, 3 models | see [`modules/ollama`](tofu/modules/ollama/README.md) |
| `ollama_gpu_memory_mib` | `16000` | HAMi slice for Ollama |
| `hami_default_gpu_memory` | `4000` | slice for plain GPU pods |
| `install_argo_workflows` | on | |
| `install_open_webui` | off | needs `install_ollama` |
| `allowed_kubectl_ips` | `0.0.0.0/0` | restrict to your IP |
| `grafana_admin_password` | `admin` | change it |

Advisory `check` blocks print warnings (never failures) for common mistakes
such as a GPU plan not offered in the region, or Ollama plus the default slice
exceeding the card's VRAM.

## Cost

| Resource | Approx. cost |
|---|---|
| GPU node (`g2-gpu-rtx4000a1-s`) | ~$0.52/hr (~$380/month) |
| System node (`g6-standard-2`) | ~$24/month |
| Volumes (monitoring ~20 Gi, Ollama 50 Gi) | ~$7/month |

About $410/month if left running; billing stops when the cluster is destroyed.
Costs are approximate, see [Linode pricing](https://www.linode.com/pricing/).

```bash
cd tofu && tofu destroy     # stop paying
cd tofu && tofu apply -var-file=tofu.tfvars   # bring it back
```

Note: the Ollama and monitoring volumes use the `linode-block-storage-retain`
class, so they survive `tofu destroy` and keep billing until deleted in the
Linode Cloud Manager.

## Security

- API token comes from `~/.config/linode-cli` or `LINODE_TOKEN`; it is never
  written to state or git. Kubeconfigs and `*.tfvars` are git-ignored.
- A Linode Cloud Firewall allows only the Kubernetes API (443) from
  `allowed_kubectl_ips` plus intra-cluster traffic.
- Ollama, Argo (`auth_mode = "server"`, no login) and Open WebUI have no
  public endpoint; keep them behind `kubectl port-forward`.

## Repository layout

```text
.
├── tofu/                    # OpenTofu root module
│   ├── modules/             # one module per component, see modules/README.md
│   └── tofu.tfvars.example
├── examples/                # runnable smoke tests (Makefiles)
├── AGENTS.md                # contributor / agent notes
└── .github/                 # CI and Dependabot
```

Contributing: run `tofu fmt -recursive` from `tofu/`, validate the root and
each changed module (`tofu init -backend=false && tofu validate`), and sign
commits (`git commit -s`). CI also runs tflint, shellcheck, Trivy and
markdownlint.

## License

[MIT](LICENSE)
