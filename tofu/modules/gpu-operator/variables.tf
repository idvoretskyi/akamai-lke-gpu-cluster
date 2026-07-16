variable "namespace" {
  description = "Kubernetes namespace for GPU operator"
  type        = string
  default     = "gpu-operator"
}

variable "gpu_operator_version" {
  description = "Version of NVIDIA GPU Operator Helm chart"
  type        = string
  default     = "v26.3.2" # Latest stable version
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

variable "controller_node_selector" {
  description = "nodeSelector to pin the GPU Operator controller onto a specific node pool (e.g. the system pool). The GPU operands always run on the GPU nodes regardless. Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "gpu_node_toleration" {
  description = "Taint that the GPU nodes carry, which the operator's DaemonSet operands (driver, toolkit, device-plugin, DCGM, GFD, NFD worker) must tolerate so they keep scheduling onto the GPU pool. Null when GPU nodes are not tainted (chart defaults apply)."
  type = object({
    key    = string
    value  = string
    effect = string
  })
  default = null
}
