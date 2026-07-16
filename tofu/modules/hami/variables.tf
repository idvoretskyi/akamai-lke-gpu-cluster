variable "namespace" {
  description = "Kubernetes namespace for HAMi"
  type        = string
  default     = "hami-system"
}

variable "hami_version" {
  description = "Version of the HAMi Helm chart"
  type        = string
  default     = "2.9.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.hami_version))
    error_message = "hami_version must be in the format 'X.Y.Z' (e.g. '2.9.0')."
  }
}

variable "device_split_count" {
  description = "Number of vGPU slices each physical GPU is split into (HAMi devicePlugin.deviceSplitCount). E.g. 10 lets 10 pods share one physical GPU."
  type        = number
  default     = 10

  validation {
    condition     = var.device_split_count >= 1
    error_message = "device_split_count must be at least 1."
  }
}

variable "device_memory_scaling" {
  description = "HAMi devicePlugin.deviceMemoryScaling — oversubscription ratio for GPU memory (1 = no oversubscription, >1 allows scheduling more vGPU memory than physically exists)."
  type        = number
  default     = 1
}

variable "device_core_scaling" {
  description = "HAMi devicePlugin.deviceCoreScaling — oversubscription ratio for GPU compute cores (1 = no oversubscription)."
  type        = number
  default     = 1
}

variable "scheduler_policy" {
  description = "HAMi scheduler bin-packing policy for node selection (binpack concentrates workloads to free up whole nodes; spread balances across nodes)."
  type        = string
  default     = "binpack"

  validation {
    condition     = contains(["binpack", "spread"], var.scheduler_policy)
    error_message = "scheduler_policy must be either 'binpack' or 'spread'."
  }
}

variable "node_selector" {
  description = "nodeSelector to pin the HAMi scheduler and webhook control-plane components onto a specific node pool (e.g. the system pool). The devicePlugin DaemonSet always targets GPU nodes via nvidiaNodeSelector regardless. Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "gpu_node_toleration" {
  description = "Taint that the GPU nodes carry, which the HAMi devicePlugin DaemonSet must tolerate so it keeps scheduling onto the GPU pool. Null when GPU nodes are not tainted (chart defaults apply)."
  type = object({
    key    = string
    value  = string
    effect = string
  })
  default = null
}

variable "nvidia_node_selector" {
  description = "nodeSelector HAMi's devicePlugin uses to target GPU nodes (devicePlugin.nvidiaNodeSelector). Must match a label present on the GPU node pool."
  type        = map(string)
  default     = { gpu = "on" }
}

variable "runtime_class_name" {
  description = "Container RuntimeClass the devicePlugin pod runs under, and that HAMi's scheduler injects into GPU workload pods, so the driver/libraries are actually visible. Must be a legacy (non-CDI) NVIDIA runtime: HAMi's GPU sharing relies on hijacking the driver library via LD_PRELOAD + NVIDIA_VISIBLE_DEVICES, which conflicts with the modern CDI-based runtime path (the GPU Operator's default 'nvidia' RuntimeClass has CDI enabled and fails to resolve HAMi's device references). The GPU Operator's toolkit also registers a 'nvidia-legacy' RuntimeClass (no CDI) that works correctly here."
  type        = string
  default     = "nvidia-legacy"
}

variable "nvidia_driver_root" {
  description = "Host path where the NVIDIA driver is installed, as mounted by the GPU Operator's containerized driver (devicePlugin.nvidiaDriverRoot). Required for the devicePlugin to find the driver/NVML libraries when the driver is installed by the GPU Operator rather than directly on the host at '/'."
  type        = string
  default     = "/run/nvidia/driver"
}

variable "wait_for_toolkit_ready" {
  description = "Gate the devicePlugin startup on the GPU Operator's toolkit readiness marker (devicePlugin.gpuOperatorToolkitReady), avoiding a race where the plugin starts before the container toolkit/runtime is configured."
  type        = bool
  default     = true
}

variable "scheduler_leader_elect" {
  description = "Enable HAMi scheduler leader election (scheduler.leaderElect). The chart adds hard pod anti-affinity to the scheduler Deployment whenever this is true, which deadlocks rolling updates on a single-node system pool (the new replica can never schedule alongside the old one, and the GPU pool is tainted). Defaults to false for this repo's single system-node lab topology; only 1 replica runs either way when false."
  type        = bool
  default     = false
}
