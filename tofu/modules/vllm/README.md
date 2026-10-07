# vLLM Module

Installs [vLLM](https://docs.vllm.ai/) with the
[vllm-project/production-stack](https://github.com/vllm-project/production-stack)
Helm chart (`vllm-stack`), so the GPU node can serve one model over vLLM's
OpenAI-compatible API, with Prometheus metrics.

This module is opt-in (`install_vllm = false` at the root). Ollama stays the
default engine; see [Ollama or vLLM](#ollama-or-vllm).

## Overview

- Runs a single vLLM engine on the GPU pool. The chart's router, LMCache
  server and LoRA controller are disabled: they only pay off with several
  engine replicas, and this cluster has one GPU.
- Serves exactly one Hugging Face model (`model`). vLLM pre-allocates
  `gpu_memory_utilization` of the GPU memory it is given at startup.
- Gives the engine the whole GPU through HAMi (`nvidia.com/gpumem`, default
  20000 MiB), like the Ollama module.
- Caches weights on a persistent volume (`HF_HOME=/data`), so restarts don't
  re-download them.
- Creates a `ServiceMonitor` when `enable_service_monitor = true`, so the
  kube-prometheus-stack Prometheus scrapes `vllm:*` metrics (time to first
  token, throughput, KV cache usage, queue depth).
- ClusterIP only. Reach it with `kubectl port-forward`; no API key is set, so
  it is not exposed publicly.

## Requirements

- GPU Operator (driver/toolkit) and, when `gpu_memory_mib` is set, HAMi.
- A checkpoint vLLM can load that fits the GPU. On a 20 GB RTX 4000 Ada that
  means a quantized checkpoint (AWQ, GPTQ or FP8) for anything above ~8B
  parameters. vLLM does not load Ollama's GGUF models.
- `hf_token` for gated models (stored in a Kubernetes Secret, injected as
  `HF_TOKEN`).

## Usage

```hcl
module "vllm" {
  source = "./modules/vllm"

  namespace              = "vllm"
  chart_version          = "0.1.13"
  model                  = "Qwen/Qwen3-8B-AWQ"
  gpu_memory_mib         = 20000
  enable_service_monitor = true
  node_selector          = local.gpu_node_labels
  gpu_node_toleration    = local.gpu_node_toleration

  depends_on = [module.gpu_operator, module.hami]
}
```

## First install

vLLM downloads the model from Hugging Face before its server starts
listening, so the pod is not Ready until the download and load finish.
`timeout` defaults to 3600 seconds, and the engine's startup probe is sized
from it. As in the Ollama module, the release is not atomic: if the apply
times out, the partial download stays on the volume, and re-running
`tofu apply` resumes it (`upgrade_install = true` adopts the existing
release).

Follow progress with:

```bash
kubectl logs -n vllm deploy/vllm-llm-deployment-vllm -f
```

## Accessing vLLM

```bash
kubectl port-forward --namespace vllm service/vllm-llm-engine-service 8000:80

curl http://localhost:8000/v1/models
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen3-8B-AWQ","messages":[{"role":"user","content":"Hello"}]}'
curl -s http://localhost:8000/metrics | grep '^vllm:'
```

Resource names include `model_name` (default `llm`): the service is
`vllm-<model_name>-engine-service`.

## Ollama or vLLM

| | Ollama (default) | vLLM (opt-in) |
|---|---|---|
| Models per pod | Many, hot-swapped (one loaded at a time) | One |
| Weights | GGUF from ollama.com | Hugging Face (safetensors; AWQ/GPTQ/FP8 to fit 20 GB) |
| GPU memory | Allocates per loaded model | Pre-allocates `gpu_memory_utilization` at startup |
| Concurrency | Basic | Continuous batching, prefix caching |
| Metrics | None for Prometheus | `vllm:*` metrics via ServiceMonitor |
| Start time | Fast after first pull | Minutes (load + CUDA graph capture) |

Both engines want the whole card by default. Running both at once needs HAMi
and `ollama_gpu_memory_mib + vllm_gpu_memory_mib` within the card's VRAM; the
root module's `llm_engines_share_one_gpu` check warns otherwise.

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"vllm"` |
| `chart_version` | vllm-stack chart version | `"0.1.13"` |
| `image_repository` | Engine image repository | `"vllm/vllm-openai"` |
| `image_tag` | Engine image tag (pinned; `latest` rejected) | `"v0.31.0"` |
| `timeout` | Helm wait timeout in seconds; sizes the startup probe | `3600` |
| `model` | Hugging Face repo id to serve | `"Qwen/Qwen3-8B-AWQ"` |
| `model_name` | Short name used in resource names | `"llm"` |
| `model_revision` | HF revision to pin | `null` |
| `hf_token` | HF token for gated models (sensitive) | `null` |
| `max_model_len` | `--max-model-len` | `8192` |
| `gpu_memory_utilization` | `--gpu-memory-utilization` | `0.9` |
| `dtype` | `--dtype` | `"auto"` |
| `extra_args` | Extra `vllm serve` arguments | `[]` |
| `gpu_memory_mib` | HAMi `nvidia.com/gpumem`; `null` omits it | `20000` |
| `node_selector` | Node labels for the GPU pool | `{}` |
| `gpu_node_toleration` | GPU node taint to tolerate | `null` |
| `resources` | CPU/host-memory requests and limits | See variables.tf |
| `shm_size` | `/dev/shm` size (counts against the memory limit) | `"2Gi"` |
| `storage_size` | Model cache PVC size | `"50Gi"` |
| `storage_class` | Model cache PVC StorageClass | `"linode-block-storage-retain"` |
| `enable_service_monitor` | Create a Prometheus ServiceMonitor | `false` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | vLLM namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `service_name` | Engine service name for port-forwarding (port 80) |
| `deployment_name` | Engine Deployment name |
| `model` | Served model |
| `validation_commands` | Port-forward, API, metrics and GPU check commands |

## Notes

- vLLM holds the whole GPU while it runs. Other GPU pods can't schedule until
  you set `install_vllm = false` at the root, or lower `gpu_memory_mib` so
  HAMi can share the card.
- The volume uses the Retain storage class: removing the release keeps the
  Linode volume (and its cost). Delete it in Cloud Manager when no longer
  needed.
