variable "namespace" {
  description = "Kubernetes namespace for GPU operator"
  type        = string
  default     = "gpu-operator"
}

variable "chart_version" {
  description = "Version of NVIDIA GPU Operator Helm chart"
  type        = string
  default     = "v26.7.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'vX.Y.Z' (e.g. 'v26.7.1')."
  }
}

variable "install_driver" {
  description = "Install NVIDIA driver (set to true for most cloud environments)"
  type        = bool
  default     = true
}

variable "device_plugin_enabled" {
  description = "Enable the GPU Operator's stock NVIDIA device plugin. Set false when HAMi (or another GPU-virtualization device plugin) manages GPU scheduling instead — the operator then only provides the driver, container toolkit, DCGM, and GFD."
  type        = bool
  default     = true
}

variable "enable_dcgm_exporter" {
  description = "Enable DCGM Exporter for GPU metrics in Prometheus"
  type        = bool
  default     = true
}

variable "enable_node_status_exporter" {
  description = "Enable Node Status Exporter"
  type        = bool
  default     = true
}

variable "node_selector" {
  description = "nodeSelector to pin the GPU Operator controller onto a specific node pool (e.g. the system pool). The GPU operands always run on the GPU nodes regardless. Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "gpu_node_toleration" {
  description = "Taint that the GPU nodes carry, which the operator's DaemonSet operands (driver, toolkit, device-plugin, DCGM, GFD, NFD worker) must tolerate so they keep scheduling onto the GPU pool. Null when GPU nodes are not tainted (chart defaults apply)."
  type = object({
    key    = string
    value  = optional(string) # unused: templates tolerate with operator: Exists
    effect = string
  })
  default = null
}

variable "timeout" {
  description = "Seconds to wait for the Helm release to become ready (install/upgrade). With atomic = true, a timeout triggers an automatic rollback."
  type        = number
  default     = 600

  validation {
    condition     = var.timeout >= 60
    error_message = "timeout must be at least 60 seconds."
  }
}

variable "install_toolkit" {
  description = "Deploy the operator's NVIDIA Container Toolkit DaemonSet (rewrites the node's containerd config and restarts containerd). Disable when the node image already ships the toolkit/runtime config."
  type        = bool
  default     = true
}
