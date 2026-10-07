# ─── Release ──────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace for vLLM"
  type        = string
  default     = "vllm"
}

variable "chart_version" {
  description = "Version of the vllm-project production-stack chart (vllm-stack)"
  type        = string
  default     = "0.1.13"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '0.1.13')."
  }
}

variable "image_repository" {
  description = "vLLM engine image repository"
  type        = string
  default     = "vllm/vllm-openai"
}

variable "image_tag" {
  description = "vLLM engine image tag. Pinned rather than 'latest' so applies are reproducible; newly released model architectures sometimes need a newer vLLM."
  type        = string
  default     = "v0.31.0"

  validation {
    condition     = var.image_tag != "latest" && length(var.image_tag) > 0
    error_message = "image_tag must be a pinned tag (e.g. 'v0.31.0'), not 'latest'."
  }
}

variable "timeout" {
  description = "Seconds to wait for the Helm release to become ready. The first install waits for the model download and load, so this must cover both. A timeout leaves the release in place (atomic = false), so re-running apply resumes. Also sizes the engine's startup probe."
  type        = number
  default     = 3600

  validation {
    condition     = var.timeout >= 60
    error_message = "timeout must be at least 60 seconds."
  }
}

# ─── Model ────────────────────────────────────────────────────────────────────

variable "model" {
  description = "Hugging Face model repository to serve (org/name). It must fit the GPU's VRAM on its own, with room for the KV cache."
  type        = string
  default     = "Qwen/Qwen3-8B-AWQ"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$", var.model))
    error_message = "model must be a Hugging Face repo id like 'org/name' (e.g. 'Qwen/Qwen3-8B-AWQ')."
  }
}

variable "model_name" {
  description = "Short name for the model, used in Kubernetes resource names (vllm-<name>-engine-service). Lowercase alphanumerics and dashes."
  type        = string
  default     = "llm"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.model_name))
    error_message = "model_name must be 1-32 lowercase alphanumerics or dashes, not starting or ending with a dash."
  }
}

variable "model_revision" {
  description = "Hugging Face revision (branch, tag or commit) to pin the model to. Null uses the default branch."
  type        = string
  default     = null
}

variable "hf_token" {
  description = "Hugging Face token, only needed for gated models. Stored in a Kubernetes Secret and injected as HF_TOKEN."
  type        = string
  default     = null
  sensitive   = true
}

variable "max_model_len" {
  description = "Maximum context length in tokens (--max-model-len). vLLM reserves KV cache for it up front; keep it modest on a 20 GB card."
  type        = number
  default     = 8192

  validation {
    condition     = var.max_model_len >= 2048
    error_message = "max_model_len must be at least 2048."
  }
}

variable "gpu_memory_utilization" {
  description = "Fraction of the GPU memory vLLM may use for weights, activations and KV cache (--gpu-memory-utilization). vLLM pre-allocates this at startup. Under HAMi it is a fraction of the gpumem slice, not the whole card."
  type        = number
  default     = 0.9

  validation {
    condition     = var.gpu_memory_utilization > 0 && var.gpu_memory_utilization <= 1
    error_message = "gpu_memory_utilization must be in (0, 1]."
  }
}

variable "dtype" {
  description = "Model dtype (--dtype). 'auto' lets vLLM pick from the checkpoint."
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "half", "float16", "bfloat16", "float", "float32"], var.dtype)
    error_message = "dtype must be one of auto, half, float16, bfloat16, float, float32."
  }
}

variable "extra_args" {
  description = "Extra command-line arguments for `vllm serve`, e.g. [\"--enable-auto-tool-choice\", \"--tool-call-parser\", \"hermes\"]."
  type        = list(string)
  default     = []
}

# ─── GPU / Scheduling ────────────────────────────────────────────────────────

variable "gpu_memory_mib" {
  description = "HAMi vGPU memory to request (nvidia.com/gpumem, MiB). Set to the card's full VRAM to give vLLM the whole GPU. Null omits it, so HAMi applies its default slice — or, without HAMi, the whole GPU."
  type        = number
  default     = 20000

  validation {
    condition     = var.gpu_memory_mib == null || var.gpu_memory_mib >= 1024
    error_message = "gpu_memory_mib must be null or at least 1024."
  }
}

variable "node_selector" {
  description = "Node labels pinning vLLM onto the GPU pool. Empty schedules anywhere a GPU is available."
  type        = map(string)
  default     = {}
}

variable "gpu_node_toleration" {
  description = "Taint carried by the GPU nodes, which vLLM must tolerate. Null when GPU nodes are not tainted."
  type = object({
    key    = string
    value  = optional(string) # unused: the template tolerates with operator: Exists
    effect = string
  })
  default = null
}

variable "resources" {
  description = "CPU and host-memory requests/limits for the engine container. Host memory holds the tokenizer, CUDA graphs and the model while it is loaded onto the GPU."
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
    requests = { cpu = "2", memory = "8Gi" }
    limits   = { cpu = "4", memory = "12Gi" }
  }
}

variable "shm_size" {
  description = "Size of the /dev/shm emptyDir (memory-backed). vLLM uses shared memory between its processes; it counts against the pod's memory limit."
  type        = string
  default     = "2Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.shm_size))
    error_message = "shm_size must be a quantity in Mi or Gi (e.g. '2Gi')."
  }
}

# ─── Storage ─────────────────────────────────────────────────────────────────

variable "storage_size" {
  description = "Size of the PVC holding the Hugging Face cache (HF_HOME=/data)."
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.storage_size))
    error_message = "storage_size must be a quantity in Gi or Ti (e.g. '50Gi')."
  }
}

variable "storage_class" {
  description = "StorageClass for the model PVC. The Retain class keeps downloaded weights if the release is removed."
  type        = string
  default     = "linode-block-storage-retain"
}

# ─── Monitoring ──────────────────────────────────────────────────────────────

variable "enable_service_monitor" {
  description = "Create a ServiceMonitor so Prometheus scrapes vLLM's /metrics (TTFT, throughput, KV cache usage). Requires the Prometheus Operator CRDs (kube-prometheus-stack)."
  type        = bool
  default     = false
}
