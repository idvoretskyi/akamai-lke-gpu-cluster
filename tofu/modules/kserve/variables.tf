variable "namespace" {
  description = "Kubernetes namespace for the KServe control plane. Labelled control-plane, so InferenceServices must live elsewhere."
  type        = string
  default     = "kserve"
}

variable "chart_version" {
  description = "KServe version for the kserve-crd, kserve-resources and kserve-runtime-configs charts (format: 'vX.Y.Z'). Also selects the Hugging Face runtime image tag ('<version>-gpu')."
  type        = string
  default     = "v0.20.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'vX.Y.Z' (e.g. 'v0.20.0')."
  }
}

variable "ingress_domain" {
  description = "Domain KServe uses for InferenceService hostnames (<name>-<namespace>.<domain>). Without real DNS, send requests with a matching Host header."
  type        = string
  default     = "kserve.local"
}

variable "vllm_shm_size" {
  description = "Size of the in-memory /dev/shm volume given to Hugging Face (vLLM) runtime pods."
  type        = string
  default     = "2Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.vllm_shm_size))
    error_message = "vllm_shm_size must be a quantity in Mi or Gi (e.g. '2Gi')."
  }
}

variable "node_selector" {
  description = "nodeSelector for the KServe controller. Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Seconds to wait for each Helm release to become ready (install/upgrade). With atomic = true, a timeout triggers an automatic rollback."
  type        = number
  default     = 600

  validation {
    condition     = var.timeout >= 60
    error_message = "timeout must be at least 60 seconds."
  }
}
