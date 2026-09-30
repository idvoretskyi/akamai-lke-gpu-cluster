# ─── Release ──────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace for vLLM"
  type        = string
  default     = "vllm"
}

variable "release_name" {
  description = "Helm release name; also prefixes the engine Service name (<release>-coder-engine-service)"
  type        = string
  default     = "vllm"
}

variable "chart_version" {
  description = "Version of the vllm-stack Helm chart (vllm-project/production-stack)"
  type        = string
  default     = "0.1.13"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '0.1.13')."
  }
}

variable "image_repository" {
  description = "vLLM container image repository"
  type        = string
  default     = "vllm/vllm-openai"
}

variable "image_tag" {
  description = "vLLM container image tag. Pinned: never 'latest'."
  type        = string
  default     = "v0.30.0"

  validation {
    condition     = var.image_tag != "latest" && can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.image_tag))
    error_message = "image_tag must be a pinned vLLM release tag such as 'v0.30.0', not 'latest'."
  }
}

variable "timeout" {
  description = "Seconds Helm waits for the release. The first install downloads the model and captures CUDA graphs, so keep this above startup_timeout_seconds."
  type        = number
  default     = 2400

  validation {
    condition     = var.timeout >= 60
    error_message = "timeout must be at least 60 seconds."
  }
}

variable "startup_timeout_seconds" {
  description = "Budget for the startup probe (/health) before the container is restarted. Covers the first model download and CUDA graph capture."
  type        = number
  default     = 1500

  validation {
    condition     = var.startup_timeout_seconds >= 1200
    error_message = "startup_timeout_seconds must be at least 1200 (20 minutes)."
  }
}

# ─── Model ────────────────────────────────────────────────────────────────────

variable "model_repo" {
  description = "Hugging Face repository id of the model to serve"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.model_repo))
    error_message = "model_repo must be a Hugging Face repository id such as 'openai/gpt-oss-20b'."
  }
}

variable "served_model_name" {
  description = "Model name exposed by the API (/v1/models); clients use it as the model id"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]*$", var.served_model_name))
    error_message = "served_model_name must be lowercase letters, digits, '.', '_' or '-'."
  }
}

variable "max_model_len" {
  description = "Maximum context length in tokens (--max-model-len). Must fit the KV cache left after the weights."
  type        = number

  validation {
    condition     = var.max_model_len >= 4096
    error_message = "max_model_len must be at least 4096."
  }
}

variable "max_num_seqs" {
  description = "Maximum concurrent sequences (--max-num-seqs). Low for a single user: fewer CUDA graphs to capture and more KV cache per sequence."
  type        = number
  default     = 4

  validation {
    condition     = var.max_num_seqs >= 1
    error_message = "max_num_seqs must be at least 1."
  }
}

variable "tool_call_parser" {
  description = "vLLM tool-call parser matching the model's chat template (e.g. 'openai' for gpt-oss, 'qwen3_coder' for Qwen3-Coder)"
  type        = string
}

variable "reasoning_parser" {
  description = "vLLM reasoning parser, or null for models without a separate reasoning channel (e.g. 'openai_gptoss' for gpt-oss)"
  type        = string
  default     = null
}

variable "kv_cache_dtype" {
  description = "KV cache dtype (--kv-cache-dtype). fp8 halves KV memory and is supported on Ada."
  type        = string
  default     = "fp8"

  validation {
    condition     = contains(["auto", "fp8", "fp8_e4m3", "fp8_e5m2"], var.kv_cache_dtype)
    error_message = "kv_cache_dtype must be one of: auto, fp8, fp8_e4m3, fp8_e5m2."
  }
}

variable "gpu_memory_utilization" {
  description = "Fraction of GPU memory vLLM may use for weights, activations and KV cache (--gpu-memory-utilization)"
  type        = number
  default     = 0.92

  validation {
    condition     = var.gpu_memory_utilization > 0.5 && var.gpu_memory_utilization <= 0.97
    error_message = "gpu_memory_utilization must be greater than 0.5 and at most 0.97."
  }
}

variable "extra_args" {
  description = "Additional vLLM arguments appended verbatim"
  type        = list(string)
  default     = []
}

# ─── Credentials ──────────────────────────────────────────────────────────────

variable "api_key" {
  description = "API key clients must send as a Bearer token. Null generates a random key (see the api_key output)."
  type        = string
  default     = null
  sensitive   = true
}

variable "hf_token" {
  description = "Hugging Face token for gated models; null when the model is public"
  type        = string
  default     = null
  sensitive   = true
}

# ─── Scheduling / GPU ─────────────────────────────────────────────────────────

variable "hami_full_gpu" {
  description = "Schedule through HAMi and request the whole card (nvidia.com/gpumem-percentage and nvidia.com/gpucores at 100). Set true when HAMi is installed; without it a plain nvidia.com/gpu request only gets HAMi's default memory slice."
  type        = bool
  default     = false
}

variable "runtime_class_name" {
  description = "RuntimeClass for the vLLM pod; 'nvidia' is the runtime the LKE GPU image configures in containerd"
  type        = string
  default     = "nvidia"
}

variable "node_selector" {
  description = "Node labels the pod must match (rendered as required node affinity), e.g. the GPU pool labels"
  type        = map(string)
  default     = {}
}

variable "gpu_node_toleration" {
  description = "Taint the GPU nodes carry; null when they are not tainted"
  type = object({
    key    = string
    value  = optional(string) # unused: tolerated with operator: Exists
    effect = string
  })
  default = null
}

variable "resources" {
  description = "CPU/memory for the vLLM container. No CPU limit; the memory limit is generous because loading a checkpoint needs host RAM."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ memory = string })
  })
  default = {
    requests = { cpu = "2", memory = "6Gi" }
    limits   = { memory = "12Gi" }
  }
}

variable "shm_size" {
  description = "Size limit of the in-memory /dev/shm volume"
  type        = string
  default     = "2Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.shm_size))
    error_message = "shm_size must be a Kubernetes quantity in Mi or Gi (e.g. '2Gi')."
  }
}

# ─── Storage ──────────────────────────────────────────────────────────────────

variable "cache_size" {
  description = "Size of the model cache PVC (HF_HOME). Linode Block Storage minimum is 10Gi."
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[0-9]+Gi$", var.cache_size)) && try(tonumber(trimsuffix(var.cache_size, "Gi")) >= 10, false)
    error_message = "cache_size must be in Gi and at least '10Gi' (Linode Block Storage minimum)."
  }
}

variable "cache_storage_class" {
  description = "StorageClass for the model cache. 'linode-block-storage' deletes the volume with the PVC, so destroying the cluster leaves nothing billed; 'linode-block-storage-retain' keeps the weights but orphans a billed volume on every destroy."
  type        = string
  default     = "linode-block-storage"
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

variable "enable_monitoring" {
  description = "Create a ServiceMonitor for vLLM /metrics and the upstream vLLM Grafana dashboards. Requires the Prometheus Operator CRDs (kube-prometheus-stack)."
  type        = bool
  default     = false
}
