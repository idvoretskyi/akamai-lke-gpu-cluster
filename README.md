# Akamai LKE + KServe GPU Reference Architecture

[![CI](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/idvoretskyi/akamai-lke-gpu-cluster/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-%3E%3D1.9-844FBA?logo=opentofu&logoColor=white)](https://opentofu.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)

A baseline for serving LLMs on Akamai (Linode) Kubernetes Engine with
[KServe](https://kserve.github.io/website/) and [vLLM](https://docs.vllm.ai/):
one LKE cluster on the cheapest single-GPU plan (NVIDIA RTX 4000 Ada, 20 GB),
the platform installed by OpenTofu, and the model itself delivered by
[Argo CD](https://argo-cd.readthedocs.io/) from this repository. Everything is
open source from the CNCF and Linux Foundation ecosystems; destroy it when you
are done.

## Architecture

```text
                       ┌──────────────────────── LKE cluster ────────────────────────┐
 you ── kubectl ──────►│ system pool (g6-standard-4)          GPU pool (RTX 4000 Ada) │
   port-forward        │                                      taint nvidia.com/gpu    │
                       │  Envoy Gateway ── Gateway ─HTTPRoute─► InferenceService      │
                       │  (Gateway API)   kserve-ingress-       "qwen3"               │
                       │                  gateway               KServe HF runtime     │
                       │                                         = vLLM, Qwen3-8B-FP8 │
                       │  KServe controller (Standard mode) ──► Deployment/Service/HPA│
                       │  cert-manager (KServe webhook TLS)                           │
                       │  Argo CD ◄── gitops/vllm in Git                              │
                       │  Prometheus + Grafana ◄── DCGM GPU metrics, ServiceMonitors  │
                       │  metrics-server, GPU Operator controller                     │
                       └──────────────────────────────────────────────────────────────┘
```

| Layer | Component | Project | Managed by |
|---|---|---|---|
| Infrastructure | LKE cluster, node pools, Cloud Firewall | Akamai | OpenTofu |
| GPU | [GPU Operator](https://github.com/NVIDIA/gpu-operator) (device plugin, GFD, DCGM) | NVIDIA | OpenTofu |
| Ingress | [Envoy Gateway](https://gateway.envoyproxy.io/) + Gateway API | CNCF (Envoy) / Kubernetes SIG | OpenTofu |
| Serving | [KServe](https://kserve.github.io/website/) Standard mode + [cert-manager](https://cert-manager.io/) | CNCF incubating / graduated | OpenTofu |
| Inference engine | [vLLM](https://docs.vllm.ai/) via KServe's Hugging Face runtime | LF AI & Data | OpenTofu (runtime) |
| Model | `InferenceService` serving `Qwen/Qwen3-8B-FP8` | | **Argo CD** (`gitops/vllm`) |
| GitOps | [Argo CD](https://argo-cd.readthedocs.io/) | CNCF graduated | OpenTofu |
| Observability | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts), [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) | CNCF / Kubernetes SIG | OpenTofu |

The split is deliberate: OpenTofu owns the platform (things you install once
per cluster), Argo CD owns the workloads (things you change often). Swapping
the model is a Git commit, not a `tofu apply`.

## The serving story

- **KServe Standard mode.** No Knative or Istio: an `InferenceService` becomes
  a plain Deployment, Service and HPA, plus an `HTTPRoute` on the shared
  `kserve-ingress-gateway`. This is KServe's recommended mode for generative
  workloads.
- **vLLM.** KServe's Hugging Face runtime runs vLLM and exposes an
  OpenAI-compatible API under `/openai/v1`. The runtime's default image is
  KServe's CPU build, so the InferenceService requests the CUDA build
  (`kserve/huggingfaceserver:<ver>-gpu`) itself.
- **The model.** `Qwen/Qwen3-8B-FP8`: ungated (no Hugging Face token), ~9 GB
  of FP8 weights, which the Ada GPU runs natively. vLLM gets 90% of the 20 GB
  card; what the weights leave over holds the KV cache for a 32k-token
  context. One replica with a `Recreate` strategy, since there is one GPU.
- **Private by default.** The Envoy proxy behind the Gateway is a ClusterIP
  service. Requests reach it through `kubectl port-forward` and pick the
  InferenceService with the `Host` header
  (`qwen3-vllm.kserve.local`).

Measured on `de-fra-2` (KServe v0.20.0, vLLM v0.24.0): weights download in
~30 s, vLLM loads and compiles in ~2 min, 8.8 GiB of weights leave a 7.6 GiB
KV cache (~55k tokens), and a single stream decodes at ~35 tokens/s.

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

Timing: ~15-20 minutes for the cluster and platform. Argo CD then syncs the
InferenceService; the first start pulls the ~7 GB vLLM image and ~9 GB of
weights, so allow another ~10 minutes before it reports `READY=True`.

Prerequisites: [OpenTofu](https://opentofu.org) >= 1.9, `kubectl`, `jq`, and
`linode-cli` (the provider reads its token from `~/.config/linode-cli`, else
`LINODE_TOKEN`). `kubectl` is also used by `tofu apply` to merge the
kubeconfig.

## Try it

```bash
make -C examples/kserve-chat wait                # model loaded and serving
make -C examples/kserve-chat port-forward        # terminal 1: Gateway -> :8080
make -C examples/kserve-chat models chat         # terminal 2
make -C examples/kserve-chat chat PROMPT="What is the Gateway API?"
make -C examples/kserve-chat stream gpu          # streamed reply; nvidia-smi

make -C examples/argocd apps status              # GitOps view of the model
```

The endpoint is OpenAI-compatible, so any OpenAI client works with base URL
`http://localhost:8080/openai/v1`, model `qwen3`, any API key, and the
`Host: qwen3-vllm.kserve.local` header.

Web UIs are ClusterIP only; reach them with `kubectl port-forward`:

| UI | Command | URL |
|---|---|---|
| Model API (via Gateway) | `make -C examples/kserve-chat port-forward` | <http://localhost:8080/openai/v1> |
| Argo CD (user `admin`, `make -C examples/argocd password`) | `kubectl port-forward -n argocd svc/argo-cd-argocd-server 8081:80` | <http://localhost:8081> |
| Grafana (admin/admin by default) | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` | <http://localhost:3000> |
| Prometheus | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | <http://localhost:9090> |

`tofu output inference_commands` prints the raw `kubectl`/`curl` equivalents,
and every component has a `*_validation_commands` output.

## Changing the model (GitOps)

The bootstrap Application `vllm` syncs [`gitops/vllm`](gitops/vllm/) from
`gitops_repo_url` at `gitops_target_revision`, with automated prune and
self-heal. To serve something else:

1. Fork the repository and set `gitops_repo_url` to the fork (Argo CD reads it
   anonymously, so it must be public, or add repo credentials to Argo CD).
2. Edit [`gitops/vllm/inferenceservice.yaml`](gitops/vllm/inferenceservice.yaml):
   `storageUri: hf://<org>/<model>` and the vLLM `args`. For the 20 GB card,
   `Qwen/Qwen3-14B-FP8` (~16 GB of weights) also fits with
   `--max-model-len=8192`.
3. Commit and push. Argo CD recreates the predictor pod with the new model
   (`make -C examples/argocd refresh` skips the ~3-minute poll).

Gated models (Llama, Gemma) need a Hugging Face token; see
[`gitops/vllm/README.md`](gitops/vllm/README.md). To test changes on a
branch first, set `gitops_target_revision` to the branch name.

## Scheduling

- Pools are labelled `nodepool.lke/role=system|gpu`; every platform component
  is pinned to the system pool.
- With `dedicate_gpu_nodes = true` (default) the GPU pool carries the taint
  `nvidia.com/gpu=present:NoSchedule`. GPU workloads need this toleration, a
  `nodepool.lke/role: gpu` selector and an `nvidia.com/gpu` limit, as the
  InferenceService does:

```yaml
spec:
  predictor:
    nodeSelector:
      nodepool.lke/role: gpu
    tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
    model:
      resources:
        limits:
          nvidia.com/gpu: "1"
```

- The InferenceService holds the only GPU. Other GPU pods (such as
  [`examples/gpu-validation`](examples/gpu-validation/)) stay `Pending` until
  it is removed or a second GPU node is added (`gpu_node_count = 2`).
- LKE GPU nodes already ship the NVIDIA driver, container toolkit and an
  `nvidia` containerd runtime, so the GPU Operator installs neither.

## Configuration

All settings live in `tofu/tofu.tfvars.example`, which is the source of truth
for variable names and defaults. The ones you are most likely to change:

| Variable | Default | Notes |
|---|---|---|
| `region` | `de-fra-2` | must offer the RTX 4000 Ada plan |
| `gpu_node_type` | `g2-gpu-rtx4000a1-s` | |
| `system_node_type` | `g6-standard-4` | 8 GB; must differ from `gpu_node_type` |
| `install_kserve` | on | also installs cert-manager and Envoy Gateway |
| `gateway_service_type` | `ClusterIP` | `LoadBalancer` = public, unauthenticated NodeBalancer |
| `install_argo_cd` | on | bootstraps the `vllm` Application |
| `gitops_repo_url`, `gitops_target_revision`, `gitops_path` | this repo, `main`, `gitops/vllm` | where the model comes from |
| `allowed_kubectl_ips` | `0.0.0.0/0` | restrict to your IP |
| `grafana_admin_password` | `admin` | change it |

Advisory `check` blocks print warnings (never failures) for common mistakes,
such as a GPU plan not offered in the region or a public Gateway.

## Cost

| Resource | Approx. cost |
|---|---|
| GPU node (`g2-gpu-rtx4000a1-s`) | ~$0.52/hr (~$380/month) |
| System node (`g6-standard-4`) | ~$48/month |
| Volumes (Prometheus 15 Gi, Grafana 5 Gi) | ~$2/month |
| NodeBalancer (only with `gateway_service_type = "LoadBalancer"`) | ~$10/month |

About $430/month if left running; billing stops when the cluster is
destroyed. Costs are approximate, see
[Linode pricing](https://www.linode.com/pricing/).

```bash
cd tofu && tofu destroy     # stop paying
cd tofu && tofu apply -var-file=tofu.tfvars   # bring it back
```

The monitoring volumes use the `linode-block-storage` class, so `tofu
destroy` deletes them too. Model weights live in the predictor pod's
ephemeral storage and are downloaded again on each start.

## Upgrading an existing cluster

Clusters created before the KServe rebuild used the
`linode-block-storage-retain` class for the Prometheus and Grafana volumes. A
PVC's storage class is immutable, so applying the new default in place fails
when Helm tries to patch Grafana's PVC (and the release rolls back). Either:

- **Recreate** (the intended path, matching the destroy/recreate cost model):
  `tofu destroy`, delete the retained volumes left in Cloud Manager
  (`linode-cli volumes list`), then `tofu apply`; or
- **Keep the old class**: set `monitoring_storage_class =
  "linode-block-storage-retain"` in `tofu.tfvars` before applying.

## Security

- API token comes from `~/.config/linode-cli` or `LINODE_TOKEN`; it is never
  written to state or git. Kubeconfigs and `*.tfvars` are git-ignored.
- A Linode Cloud Firewall allows only the Kubernetes API (443) from
  `allowed_kubectl_ips` plus intra-cluster traffic.
- The model endpoint has no authentication. It stays private (ClusterIP
  Gateway) unless you set `gateway_service_type = "LoadBalancer"`; put
  authentication in front of it before doing that.
- Argo CD, Grafana and Prometheus have no public endpoint; reach them with
  `kubectl port-forward`.

## Repository layout

```text
.
├── tofu/                    # OpenTofu root module (platform)
│   ├── modules/             # one module per component, see modules/README.md
│   └── tofu.tfvars.example
├── gitops/                  # workloads synced by Argo CD
│   └── vllm/                # the InferenceService
├── examples/                # runnable smoke tests (Makefiles)
├── AGENTS.md                # contributor / agent notes
└── .github/                 # CI and Dependabot
```

Contributing: run `tofu fmt -recursive` from `tofu/`, validate the root and
each changed module (`tofu init -backend=false && tofu validate`), and sign
commits (`git commit -s`). CI also runs tflint, shellcheck, Trivy,
markdownlint, yamllint and `helm lint`/`kustomize build` on the GitOps tree
and local charts.

## License

[MIT](LICENSE)
