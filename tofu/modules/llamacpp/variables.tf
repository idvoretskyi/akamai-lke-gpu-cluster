# ─── Release ──────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace for llama.cpp"
  type        = string
  default     = "llamacpp"
}

variable "release_name" {
  description = "Helm release name; also the Service name"
  type        = string
  default     = "llamacpp"
}

variable "chart_version" {
  description = "Version of the bjw-s app-template Helm chart"
  type        = string
  default     = "5.2.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '5.2.1')."
  }
}

variable "image_repository" {
  description = "llama.cpp server image repository"
  type        = string
  default     = "ghcr.io/ggml-org/llama.cpp"
}

variable "image_tag" {
  description = "llama.cpp server image tag (CUDA build, pinned)"
  type        = string
  default     = "server-cuda-v0.5.0"

  validation {
    condition     = can(regex("^server-cuda", var.image_tag)) && var.image_tag != "server-cuda"
    error_message = "image_tag must be a pinned CUDA server tag such as 'server-cuda-v0.5.0', not the floating 'server-cuda'."
  }
}

variable "timeout" {
  description = "Seconds Helm waits for the release; covers the first GGUF download"
  type        = number
  default     = 2400

  validation {
    condition     = var.timeout >= 60
    error_message = "timeout must be at least 60 seconds."
  }
}

variable "startup_timeout_seconds" {
  description = "Startup probe budget (/health) covering the first download and model load"
  type        = number
  default     = 1500

  validation {
    condition     = var.startup_timeout_seconds >= 1200
    error_message = "startup_timeout_seconds must be at least 1200 (20 minutes)."
  }
}

# ─── Model ────────────────────────────────────────────────────────────────────

variable "gguf_repo" {
  description = "Hugging Face GGUF repository and quant for -hf, as '<user>/<repo>:<quant>'"
  type        = string
  default     = "unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$", var.gguf_repo))
    error_message = "gguf_repo must look like '<user>/<repo>' or '<user>/<repo>:<quant>'."
  }
}

variable "served_model_name" {
  description = "Model id exposed by the API (--alias)"
  type        = string
  default     = "qwen3.8-27b"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]*$", var.served_model_name))
    error_message = "served_model_name must be lowercase letters, digits, '.', '_' or '-'."
  }
}

variable "context_size" {
  description = "Context size in tokens (-c)"
  type        = number
  default     = 32768

  validation {
    condition     = var.context_size >= 4096
    error_message = "context_size must be at least 4096."
  }
}

variable "kv_cache_type" {
  description = "KV cache type for K and V (-ctk/-ctv)"
  type        = string
  default     = "q8_0"

  validation {
    condition     = contains(["f16", "bf16", "q8_0", "q5_1", "q5_0", "q4_1", "q4_0", "iq4_nl"], var.kv_cache_type)
    error_message = "kv_cache_type must be one of: f16, bf16, q8_0, q5_1, q5_0, q4_1, q4_0, iq4_nl."
  }
}

variable "parallel" {
  description = "Number of server slots (-np); the context is split between them"
  type        = number
  default     = 1

  validation {
    condition     = var.parallel >= 1
    error_message = "parallel must be at least 1."
  }
}

variable "n_cpu_moe" {
  description = "MoE models: keep the expert weights of the first N layers in host RAM (--n-cpu-moe). 0 keeps everything on the GPU."
  type        = number
  default     = 0

  validation {
    condition     = var.n_cpu_moe >= 0
    error_message = "n_cpu_moe must be 0 or more."
  }
}

variable "n_cpu_ffn" {
  description = "Dense models: keep the FFN weights of the first N layers in host RAM (--n-cpu-ffn). 0 keeps everything on the GPU."
  type        = number
  default     = 0

  validation {
    condition     = var.n_cpu_ffn >= 0
    error_message = "n_cpu_ffn must be 0 or more."
  }
}

variable "extra_args" {
  description = "Additional llama-server arguments appended verbatim"
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
  description = "Hugging Face token for gated repositories; null when public"
  type        = string
  default     = null
  sensitive   = true
}

# ─── Scheduling / GPU ─────────────────────────────────────────────────────────

variable "hami_full_gpu" {
  description = "Schedule through HAMi and request the whole card (nvidia.com/gpumem-percentage and nvidia.com/gpucores at 100)"
  type        = bool
  default     = false
}

variable "runtime_class_name" {
  description = "RuntimeClass for the pod; 'nvidia' on the LKE GPU image"
  type        = string
  default     = "nvidia"
}

variable "node_selector" {
  description = "nodeSelector for the pod, e.g. the GPU pool labels"
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
  description = "CPU/memory for the server. Weights kept on the CPU (n_cpu_moe / n_cpu_ffn) count against the memory limit."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ memory = string })
  })
  default = {
    requests = { cpu = "2", memory = "4Gi" }
    limits   = { memory = "12Gi" }
  }
}

# ─── Storage ──────────────────────────────────────────────────────────────────

variable "cache_size" {
  description = "Size of the model cache PVC (Linode minimum 10Gi)"
  type        = string
  default     = "40Gi"

  validation {
    condition     = can(regex("^[0-9]+Gi$", var.cache_size)) && try(tonumber(trimsuffix(var.cache_size, "Gi")) >= 10, false)
    error_message = "cache_size must be in Gi and at least '10Gi'."
  }
}

variable "cache_storage_class" {
  description = "StorageClass for the model cache; the default deletes the volume on destroy"
  type        = string
  default     = "linode-block-storage"
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

variable "enable_monitoring" {
  description = "Create a ServiceMonitor for llama-server /metrics. Requires the Prometheus Operator CRDs."
  type        = bool
  default     = false
}
