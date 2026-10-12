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

You need [OpenTofu](https://opentofu.org) >= 1.9, `kubectl`, `curl`, `jq` and a Linode
account. Authenticate with `linode-cli configure` (or `export LINODE_TOKEN=...`).

```bash
git clone https://github.com/idvoretskyi/akamai-lke-gpu-cluster && cd akamai-lke-gpu-cluster/tofu
cp tofu.auto.tfvars.example tofu.auto.tfvars   # optional: the defaults work
tofu init
tofu apply
```

That is the whole install: about 15-20 minutes for the cluster and platform.
OpenTofu loads `tofu.auto.tfvars` by itself, so there is no `-var-file`, and
your kubeconfig is merged into `~/.kube/config` for you. Argo CD then deploys
the model; its first start pulls ~7 GB of image and ~9 GB of weights, so give
it another ~10 minutes. Then, from the repository root:

```bash
scripts/status.sh                 # everything healthy? is the model READY?
scripts/chat.sh "What is the Gateway API?"
```

| Script | What it does |
|---|---|
| `scripts/status.sh` | nodes, model, Argo CD app, gateway, and any unhealthy pod |
| `scripts/chat.sh "prompt"` | opens a port-forward to the private Gateway, asks the model, closes it |
| `scripts/ui.sh argocd\|grafana\|prometheus` | UI on localhost (login printed); Ctrl-C to stop |
| `scripts/gpu-test.sh` | raw `nvidia-smi` in a CUDA pod (needs a free GPU, see Scheduling) |

They are plain bash around `kubectl`, `curl` and `jq`; read them, they are short.
`tofu output next_steps` prints the same list.

The endpoint is OpenAI-compatible, so any OpenAI client works against
`http://localhost:8080/openai/v1` (run `kubectl port-forward` as `chat.sh`
does) with model `qwen3`, any API key, and the header
`Host: qwen3-vllm.kserve.local`.

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
   (it polls Git about every 3 minutes; watch with `scripts/status.sh`).

Gated models (Llama, Gemma) need a Hugging Face token; see
[`gitops/vllm/README.md`](gitops/vllm/README.md). To test changes on a
branch first, set `gitops_target_revision` to the branch name.

## Scheduling

- Pools are labelled `nodepool.lke/role=system|gpu`; every platform component
  is pinned to the system pool.
- The GPU pool always carries the taint
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
  `scripts/gpu-test.sh`) stay `Pending` until
  it is removed or a second GPU node is added (`gpu_node_count = 2`).
- LKE GPU nodes already ship the NVIDIA driver, container toolkit and an
  `nvidia` containerd runtime, so the GPU Operator installs neither.

## Configuration

The few settings people change are variables, listed in
`tofu/tofu.auto.tfvars.example` (every one is optional). Everything else, such
as chart versions, CIDRs, volume sizes and tags, is an opinionated default in
`tofu/locals.tf`.

| Variable | Default | Notes |
|---|---|---|
| `region` | `de-fra-2` | must offer the RTX 4000 Ada plan |
| `gpu_node_type` | `g2-gpu-rtx4000a1-s` | |
| `system_node_type` | `g6-standard-4` | 8 GB; must differ from `gpu_node_type` |
| `gateway_service_type` | `ClusterIP` | `LoadBalancer` = public, unauthenticated NodeBalancer |
| `gitops_repo_url`, `gitops_target_revision` | this repo, `main` | where Argo CD gets the model |
| `allowed_kubectl_ips` | `0.0.0.0/0` | restrict to your IP |
| `grafana_admin_password` | `admin` | change it |

Two advisory `check` blocks print warnings (never failures): a GPU plan that is
not offered in the region, and a public Gateway.

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
cd tofu && tofu destroy   # stop paying
cd tofu && tofu apply     # bring it back
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
  "linode-block-storage-retain"` in `tofu.auto.tfvars` before applying.

If your state was created before the "simplify" refactor (OpenTofu modules
instead of the flat layout), `tofu/moved.tf` maps every resource to its new
address, so `tofu plan` shows moves and Helm upgrades with identical values, not
a rebuild (verified on a live cluster: nothing was destroyed and no pod
restarted). Rename `tofu.tfvars` to `tofu.auto.tfvars` and delete the lines
for variables that no longer exist (`install_*`, `*_version`, ...).

Either way, the old HAMi, Ollama, Open WebUI, Argo Workflows and OpenCost
resources in the state are destroyed by the first apply. The root module still
requires the otherwise unused `hashicorp/local` provider so OpenTofu can drop
HAMi's old scratch-kubeconfig resource from the state; without it, plan and
apply fail with "Failed to load plugin schemas".

Retained volumes keep billing after their PVC is gone. Ollama's 50 Gi model
volume used `linode-block-storage-retain`, so after the first apply on a kept
cluster it is left detached in your account (~$5/month), as are the old
monitoring volumes if you recreate. Find and delete detached volumes once you
no longer need their data:

```bash
linode-cli volumes list --text --format id,label,size,linode_id   # empty linode_id = detached
linode-cli volumes delete <id>
```

## Security

- API token comes from `~/.config/linode-cli` or `LINODE_TOKEN`; it is never
  written to state or git. Kubeconfigs and `*.tfvars` files are git-ignored.
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
├── tofu/
│   ├── cluster.tf  firewall.tf  kubeconfig.tf   # LKE cluster, pools, firewall
│   ├── platform.tf                              # every Helm release, in install order
│   ├── values/                                  # one values file per chart
│   ├── charts/                                  # 2 tiny local charts (GatewayClass, Argo CD Applications)
│   ├── variables.tf  locals.tf  outputs.tf  checks.tf  moved.tf
│   └── tofu.auto.tfvars.example
├── gitops/vllm/             # the model: synced by Argo CD
├── scripts/                 # status, chat, ui, gpu-test (plain bash)
├── AGENTS.md                # contributor / agent notes
└── .github/                 # CI and Dependabot
```

Contributing: run `tofu fmt -recursive` from `tofu/`, `tofu init -backend=false
&& tofu validate`, and sign commits (`git commit -s`). CI also runs tflint,
shellcheck, Trivy, markdownlint, yamllint and `helm lint` plus `kubectl
kustomize` on the charts and the GitOps tree.

## License

[MIT](LICENSE)
