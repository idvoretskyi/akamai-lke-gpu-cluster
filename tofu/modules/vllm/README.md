# vLLM Module

Serves one model through vLLM's OpenAI-compatible API on the GPU pool, using
the [vLLM production-stack](https://github.com/vllm-project/production-stack)
Helm chart (`vllm-stack`) with its router disabled. Built as a backend for
agentic coding tools such as opencode: tool calling, prefix caching for long
repeated system prompts, and an FP8 KV cache for long contexts.

## Overview

- One engine pod, one GPU, `strategy: Recreate` (a rolling update would wait
  forever for a second GPU).
- ClusterIP Service on port 8000; reach it with `kubectl port-forward`.
- API key required on `/v1/*`: taken from `api_key`, or generated with the
  `random` provider (also when `api_key` is empty) and exposed as the
  sensitive `api_key` output.
- A NetworkPolicy denies all in-cluster ingress except from
  `allowed_ingress_namespaces` (the root passes `monitoring` for
  Prometheus). vLLM v0.30.0 serves `/invocations` (chat completions) and
  `/tokenize` without checking the key, as well as `/health` and `/metrics`,
  so the key alone does not protect the pod from other workloads.
  `kubectl port-forward` is not subject to NetworkPolicy and keeps working.
- A checksum of the credentials Secret is a pod annotation, so changing the
  key or token restarts the pod with the new values.
- Model cache PVC mounted as `HF_HOME` (`/data`).
- Optional ServiceMonitor and the upstream vLLM Grafana dashboards.

## Usage

```hcl
module "vllm" {
  source = "./modules/vllm"

  model_repo          = "QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ"
  served_model_name   = "qwen3-coder-30b"
  max_model_len       = 24576
  tool_call_parser    = "qwen3_coder"
  hami_full_gpu       = true
  node_selector       = local.gpu_node_labels
  gpu_node_toleration = local.gpu_node_toleration
  enable_monitoring   = true

  depends_on = [module.gpu_operator, module.hami]
}
```

The root module selects `model_repo`, `served_model_name`, `max_model_len`
and the parsers from the `vllm_model_profile` presets.

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Kubernetes namespace | `"vllm"` |
| `release_name` | Helm release name; prefixes the Service name | `"vllm"` |
| `chart_version` | vllm-stack chart version | `"0.1.13"` |
| `image_repository` | vLLM image repository | `"vllm/vllm-openai"` |
| `image_tag` | vLLM image tag (pinned, never `latest`) | `"v0.30.0"` |
| `timeout` | Helm wait timeout in seconds | `2400` |
| `startup_timeout_seconds` | Startup probe budget (at least 1200) | `1500` |
| `model_repo` | Hugging Face repository id | required |
| `served_model_name` | Model id exposed by `/v1/models` | required |
| `max_model_len` | `--max-model-len` | required |
| `max_num_seqs` | `--max-num-seqs` | `4` |
| `tool_call_parser` | `--tool-call-parser` | required |
| `reasoning_parser` | `--reasoning-parser`, or null | `null` |
| `kv_cache_dtype` | `--kv-cache-dtype` | `"fp8"` |
| `gpu_memory_utilization` | `--gpu-memory-utilization` | `0.92` |
| `extra_args` | Extra vLLM arguments | `[]` |
| `api_key` | API key (sensitive); null or empty generates one | `null` |
| `hf_token` | Hugging Face token for gated models (sensitive) | `null` |
| `hami_full_gpu` | Schedule via HAMi and request the whole card | `false` |
| `runtime_class_name` | Pod RuntimeClass | `"nvidia"` |
| `node_selector` | Required node labels (node affinity) | `{}` |
| `gpu_node_toleration` | GPU node taint to tolerate, or null | `null` |
| `resources` | CPU/memory requests, memory limit | 2 CPU / 6Gi, limit 12Gi |
| `shm_size` | In-memory `/dev/shm` size | `"2Gi"` |
| `cache_size` | Model cache PVC size (minimum 10Gi) | `"50Gi"` |
| `cache_storage_class` | Model cache StorageClass | `"linode-block-storage"` |
| `enable_monitoring` | ServiceMonitor and Grafana dashboards | `false` |
| `allowed_ingress_namespaces` | Namespaces allowed through the NetworkPolicy | `[]` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | vLLM namespace |
| `release_name` | Helm release name |
| `version` | Chart version |
| `status` | Helm release status |
| `service_name` | Engine Service name |
| `service_port` | Engine Service port (8000) |
| `base_url` | In-cluster OpenAI-compatible base URL |
| `served_model_name` | Model id for API requests |
| `api_key` | API key (sensitive) |
| `port_forward_command` | `kubectl port-forward` to `localhost:8000` |

## Notes

- **HAMi.** HAMi replaces the stock device plugin, and a plain
  `nvidia.com/gpu: 1` request is capped at its default memory slice
  (`hami_default_gpu_memory`, 8000 MiB). vLLM would profile only that slice.
  With `hami_full_gpu = true` the pod uses `schedulerName: hami-scheduler`
  and requests `nvidia.com/gpumem-percentage: 100` and
  `nvidia.com/gpucores: 100` (resource names from the HAMi 2.9.0 device
  config), so `nvidia-smi` in the pod and vLLM's memory profiling both see
  the whole card. HAMi's CUDA interception stays in the path; the 0.92
  utilization leaves headroom for it. Without HAMi (`install_hami = false`)
  the stock NVIDIA device plugin hands out the whole GPU and
  `hami_full_gpu` must be false.
- **Storage.** The default `linode-block-storage` class deletes the volume
  with the PVC, so `tofu destroy` leaves nothing billed, at the cost of
  downloading the weights again (about 14 to 17 GB) after each recreate.
  `linode-block-storage-retain` keeps them but leaves a billed volume behind
  on every destroy; delete it in Cloud Manager when done.
- **Not atomic.** Like the Ollama module, the release is not atomic and uses
  `upgrade_install`: a rollback of a timed-out first install would delete
  the PVC and the partial download, and a retried apply adopts the release.
- **Memory.** The GPU node (`g2-gpu-rtx4000a1-s`) has 4 vCPU and 16 GB RAM,
  about 13.5 GB allocatable. The 12Gi limit leaves room for the GPU
  Operator and HAMi operands while allowing checkpoint loading.
- The chart also renders an empty `<release>-secrets` Secret; credentials
  live in the module's own `vllm-credentials` Secret.
