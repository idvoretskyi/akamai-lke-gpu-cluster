# ─── Release ──────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace for Ollama"
  type        = string
  default     = "ollama"
}

variable "chart_version" {
  description = "Version of the otwld/ollama-helm chart"
  type        = string
  default     = "1.84.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '1.84.0')."
  }
}

variable "image_tag" {
  description = "Override the Ollama image tag (e.g. '0.35.0'). Null uses the chart's appVersion. Newly released models sometimes need a newer Ollama than the chart ships."
  type        = string
  default     = null
}

variable "timeout" {
  description = "Seconds to wait for the Helm release to become ready. The first install waits for every model in var.models to download, so this must cover the pulls. A timeout leaves the release in place (atomic = false), so re-running apply resumes the pulls."
  type        = number
  default     = 3600

  validation {
    condition     = var.timeout >= 60
    error_message = "timeout must be at least 60 seconds."
  }
}

# ─── Models ───────────────────────────────────────────────────────────────────

variable "models" {
  description = "Ollama models to pull on startup (name[:tag], as on ollama.com/library). Each should fit the GPU's VRAM on its own; only one is loaded at a time."
  type        = list(string)
  default     = ["gpt-oss:20b", "gemma4:12b", "qwen3.5:9b"]

  validation {
    condition     = alltrue([for m in var.models : can(regex("^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9._-]+)?$", m))])
    error_message = "Each model must look like 'name' or 'name:tag' (e.g. 'gemma4:12b')."
  }
}

variable "keep_alive" {
  description = "How long a model stays loaded in VRAM after its last request (OLLAMA_KEEP_ALIVE, e.g. '5m', '24h', '-1' for forever)"
  type        = string
  default     = "24h"
}

variable "context_length" {
  description = "Default context window in tokens (OLLAMA_CONTEXT_LENGTH). The KV cache grows with it; keep it modest so large models stay fully on the GPU."
  type        = number
  default     = 8192

  validation {
    condition     = var.context_length >= 2048
    error_message = "context_length must be at least 2048."
  }
}

variable "flash_attention" {
  description = "Enable flash attention (OLLAMA_FLASH_ATTENTION). Required for a quantized KV cache and reduces VRAM use."
  type        = bool
  default     = true
}

variable "kv_cache_type" {
  description = "KV cache quantization (OLLAMA_KV_CACHE_TYPE): f16, q8_0 or q4_0. q8_0 roughly halves KV memory with negligible quality loss. Needs flash_attention = true."
  type        = string
  default     = "q8_0"

  validation {
    condition     = contains(["f16", "q8_0", "q4_0"], var.kv_cache_type)
    error_message = "kv_cache_type must be one of f16, q8_0, q4_0."
  }
}

variable "extra_env" {
  description = "Additional environment variables for the Ollama container. Overrides the module's defaults on key collision."
  type        = map(string)
  default     = {}
}

# ─── GPU / Scheduling ────────────────────────────────────────────────────────

variable "gpu_memory_mib" {
  description = "HAMi vGPU memory to request (nvidia.com/gpumem, MiB). Leave headroom on a shared card (16000 of 20 GB by default) or set it to the card's full VRAM to give Ollama the whole GPU. Null omits it, so HAMi applies its default slice — or, without HAMi, the whole GPU."
  type        = number
  default     = 16000

  validation {
    condition     = var.gpu_memory_mib == null || var.gpu_memory_mib >= 1024
    error_message = "gpu_memory_mib must be null or at least 1024."
  }
}

variable "scheduler_name" {
  description = "Pod schedulerName. Set to \"hami-scheduler\" with HAMi: the default scheduler can't place a pod requesting nvidia.com/gpumem, and HAMi's webhook (failurePolicy Ignore) silently skips setting it if it isn't serving yet when the pod is created. Null leaves the cluster default."
  type        = string
  default     = null
}

variable "node_selector" {
  description = "nodeSelector pinning Ollama onto the GPU pool. Empty schedules anywhere a GPU is available."
  type        = map(string)
  default     = {}
}

variable "gpu_node_toleration" {
  description = "Taint carried by the GPU nodes, which Ollama must tolerate. Null when GPU nodes are not tainted."
  type = object({
    key    = string
    value  = optional(string) # unused: the template tolerates with operator: Exists
    effect = string
  })
  default = null
}

variable "resources" {
  description = "CPU and host-memory requests/limits. Model weights live in VRAM; host memory holds layers that spill off the GPU, so leave headroom on the GPU node."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = { cpu = "1", memory = "4Gi" }
    limits   = { cpu = "4", memory = "12Gi" }
  }
}

# ─── Storage ─────────────────────────────────────────────────────────────────

variable "storage_size" {
  description = "Size of the PVC holding downloaded models (/root/.ollama). The default models take ~29 GB."
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.storage_size))
    error_message = "storage_size must be a quantity in Gi or Ti (e.g. '50Gi')."
  }
}

variable "storage_class" {
  description = "StorageClass for the model PVC. The Retain class keeps downloaded models if the release is removed."
  type        = string
  default     = "linode-block-storage-retain"
}
