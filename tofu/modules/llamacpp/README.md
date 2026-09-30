# llama.cpp Module

Runs `llama-server` from [llama.cpp](https://github.com/ggml-org/llama.cpp)
on the GPU pool: an OpenAI-compatible server for GGUF models. Use it for
models that vLLM cannot fit on one 20 GB card, such as a dense 27B at 4-bit,
or to try MoE models with some expert weights kept in host RAM. Disabled by
default.

There is no maintained llama-server Helm chart, so the module wraps the
generic [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
chart.

## Overview

- One pod, whole GPU, `strategy: Recreate`, ClusterIP Service on port 8080.
- `-hf <repo>:<quant>` downloads the GGUF into a PVC at `/models`
  (`LLAMA_CACHE`), so restarts do not download again.
- Tool calling through the model's Jinja chat template (`--jinja`).
- Quantized KV cache (`-ctk`/`-ctv`, default `q8_0`), flash attention on.
- API key from a Secret (`LLAMA_API_KEY`), generated when null or empty
  (llama-server would otherwise run without authentication). A checksum
  annotation restarts the pod when the key changes.
- NetworkPolicy: only `allowed_ingress_namespaces` (Prometheus) may connect
  in-cluster; `kubectl port-forward` is unaffected.
- Optional ServiceMonitor for `/metrics`, authenticated with the API key.

## Usage

```hcl
module "llamacpp" {
  source = "./modules/llamacpp"

  gguf_repo           = "unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M"
  served_model_name   = "qwen3.8-27b"
  context_size        = 32768
  hami_full_gpu       = true
  node_selector       = local.gpu_node_labels
  gpu_node_toleration = local.gpu_node_toleration

  depends_on = [module.gpu_operator, module.hami]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"llamacpp"` |
| `release_name` | Helm release and Service name | `"llamacpp"` |
| `chart_version` | app-template chart version | `"5.2.1"` |
| `image_repository` | Server image repository | `"ghcr.io/ggml-org/llama.cpp"` |
| `image_tag` | Pinned CUDA server tag | `"server-cuda-v0.5.0"` |
| `timeout` | Helm wait timeout in seconds | `2400` |
| `startup_timeout_seconds` | Startup probe budget | `1500` |
| `gguf_repo` | `-hf` repository and quant | `"unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M"` |
| `served_model_name` | Model id (`--alias`) | `"qwen3.8-27b"` |
| `context_size` | `-c` | `32768` |
| `kv_cache_type` | `-ctk`/`-ctv` | `"q8_0"` |
| `parallel` | `-np` slots | `1` |
| `n_cpu_moe` | `--n-cpu-moe` (MoE layers kept on the CPU) | `0` |
| `n_cpu_ffn` | `--n-cpu-ffn` (dense FFN layers kept on the CPU) | `0` |
| `extra_args` | Extra server arguments | `[]` |
| `api_key` | API key (sensitive); null or empty generates one | `null` |
| `hf_token` | Hugging Face token (sensitive) | `null` |
| `hami_full_gpu` | Schedule via HAMi and request the whole card | `false` |
| `runtime_class_name` | Pod RuntimeClass | `"nvidia"` |
| `node_selector` | nodeSelector | `{}` |
| `gpu_node_toleration` | GPU node taint to tolerate, or null | `null` |
| `resources` | CPU/memory requests, memory limit | 2 CPU / 4Gi, limit 12Gi |
| `cache_size` | Model cache PVC size (minimum 10Gi) | `"40Gi"` |
| `cache_storage_class` | Model cache StorageClass | `"linode-block-storage"` |
| `enable_monitoring` | ServiceMonitor for `/metrics` | `false` |
| `allowed_ingress_namespaces` | Namespaces allowed through the NetworkPolicy | `[]` |

## Outputs

`namespace`, `release_name`, `version`, `status`, `service_name`,
`service_port` (8080), `base_url`, `served_model_name`, `api_key`
(sensitive) and `port_forward_command` (to `localhost:8000`, the same local
port as vLLM, so client configs work unchanged).

## Notes

- The default `UD-Q4_K_M` build of Qwen3.8-27B is 16.5 GB and fits the card
  with a 32K `q8_0` KV cache (the model uses full attention in only 16 of 64
  layers). For bigger quants, move FFN layers to the CPU with `n_cpu_ffn` and
  raise the memory limit; the node has 16 GB RAM in total.
- A dense 27B runs at roughly 15 to 20 tokens per second on this GPU, several
  times slower than the MoE models served by vLLM.
- Only one of Ollama, vLLM and llama.cpp can hold the GPU at a time; see the
  `one_gpu_model_server` check in `checks.tf`.
- HAMi and storage behave as described in the vLLM module README.
