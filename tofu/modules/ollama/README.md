# Ollama Module

Installs [Ollama](https://ollama.com/) with the
[otwld/ollama-helm](https://github.com/otwld/ollama-helm) chart, so the GPU
node can serve local LLMs over Ollama's native API and its OpenAI-compatible
`/v1` endpoint.

## Overview

- Runs one Ollama pod on the GPU pool with the whole GPU (HAMi
  `nvidia.com/gpumem` set to the card's VRAM).
- Downloads `models` onto a persistent volume on first start; later restarts
  reuse them.
- Loads one model at a time (`OLLAMA_MAX_LOADED_MODELS=1`) and keeps it in
  VRAM for `keep_alive` after the last request.
- Uses flash attention and a `q8_0` KV cache with an 8K default context, so
  ~27B Q4 models can stay fully on a 20 GB card.
- ClusterIP only. Reach it with `kubectl port-forward`; Ollama has no
  authentication, so it is not exposed publicly.

## Requirements

- GPU Operator (driver/toolkit) and, when `gpu_memory_mib` is set, HAMi.
- A GPU with enough VRAM for the largest model in `models`.

## Usage

```hcl
module "ollama" {
  source = "./modules/ollama"

  namespace           = "ollama"
  chart_version       = "1.84.0"
  models              = ["gpt-oss:20b", "gemma4:12b", "qwen3.5:9b"]
  gpu_memory_mib      = 16000
  node_selector       = local.gpu_node_labels
  gpu_node_toleration = local.gpu_node_toleration

  depends_on = [module.gpu_operator, module.hami]
}
```

## Model fit on an RTX 4000 Ada (20 GB VRAM)

The default HAMi slice is 16000 MiB, leaving ~4 GB for other GPU pods. Models
marked "needs 20000" require `ollama_gpu_memory_mib = 20000`, which takes the
whole card.

| Model | Download | Fit |
|---|---|---|
| `gpt-oss:20b` | 14 GB | Fits; MoE, fast |
| `gemma4:12b` | 7.7 GB | Fits comfortably; vision |
| `qwen3.5:9b` | 6.6 GB | Fits comfortably; vision |
| `qwen3.8:27b` | 18 GB | Needs 20000; fits at 8K context with the q8_0 KV cache |
| `gemma4:26b` | 16 GB | Needs 20000; short context only |
| Kimi K2, DeepSeek V3, GLM-5 | 400 GB+ | No; cloud-only in Ollama |

## First install

The chart pulls models in the container's `postStart` hook, so the pod is not
Ready until every model is downloaded (~29 GB for the defaults). `timeout`
defaults to 3600 seconds for this reason. The release is not atomic: if the
apply times out, the partial downloads stay on the volume and re-running
`tofu apply` resumes them: `upgrade_install = true` makes the retry upgrade the
existing release instead of failing on a name clash. The pull hook stops at
the first model that fails after three attempts, which fails the container
instead of reporting Ready with models missing.

Follow download progress with:

```bash
kubectl exec -n ollama deploy/ollama -- ollama list
```

## Accessing Ollama

```bash
kubectl port-forward --namespace ollama service/ollama 11434:11434

curl http://localhost:11434/api/tags
curl http://localhost:11434/api/chat -d '{"model":"gemma4:12b","messages":[{"role":"user","content":"Hello"}],"stream":false}'
```

OpenAI-compatible clients use base URL `http://localhost:11434/v1` with any
API key. Pull more models at any time:

```bash
kubectl exec -n ollama deploy/ollama -- ollama pull devstral-small-2:24b
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"ollama"` |
| `chart_version` | Helm chart version | `"1.84.0"` |
| `image_tag` | Override the Ollama image tag | `null` (chart appVersion) |
| `timeout` | Helm wait timeout in seconds; must cover first-time downloads | `3600` |
| `models` | Models pulled on startup | `["gpt-oss:20b", "gemma4:12b", "qwen3.5:9b"]` |
| `keep_alive` | `OLLAMA_KEEP_ALIVE` | `"24h"` |
| `context_length` | `OLLAMA_CONTEXT_LENGTH` | `8192` |
| `flash_attention` | `OLLAMA_FLASH_ATTENTION` | `true` |
| `kv_cache_type` | `OLLAMA_KV_CACHE_TYPE` (`f16`, `q8_0`, `q4_0`) | `"q8_0"` |
| `extra_env` | Extra container environment variables | `{}` |
| `gpu_memory_mib` | HAMi `nvidia.com/gpumem`; `null` omits it | `16000` |
| `node_selector` | nodeSelector for the GPU pool | `{}` |
| `gpu_node_toleration` | GPU node taint to tolerate | `null` |
| `resources` | CPU/host-memory requests and limits | See variables.tf |
| `storage_size` | Model PVC size | `"50Gi"` |
| `storage_class` | Model PVC StorageClass | `"linode-block-storage-retain"` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Ollama namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `service_name` | Service name for port-forwarding |
| `models` | Models pulled on startup |
| `validation_commands` | Port-forward, API and GPU check commands |

## Notes

- Ollama holds the whole GPU while it runs. Other GPU pods can't schedule
  until you set `install_ollama = false` at the root, or lower
  `gpu_memory_mib` so HAMi can share the card.
- The volume uses the Retain storage class: removing the release keeps the
  Linode volume (and its cost). Delete it in Cloud Manager when no longer
  needed.
