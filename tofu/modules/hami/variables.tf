# ─── Release ──────────────────────────────────────────────────────────────────

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

# ─── GPU Virtualization ───────────────────────────────────────────────────────
# Chart knobs controlling how physical GPUs are split into vGPU slices.

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

  validation {
    condition     = var.device_memory_scaling > 0
    error_message = "device_memory_scaling must be > 0."
  }
}

variable "device_core_scaling" {
  description = "HAMi devicePlugin.deviceCoreScaling — oversubscription ratio for GPU compute cores (1 = no oversubscription)."
  type        = number
  default     = 1

  validation {
    condition     = var.device_core_scaling > 0
    error_message = "device_core_scaling must be > 0."
  }
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

variable "default_gpu_memory" {
  description = "vGPU memory (MB) a Pod gets when it requests nvidia.com/gpu WITHOUT an explicit nvidia.com/gpumem limit (0 = whole physical GPU, HAMi's own chart default). See README.md 'Memory slicing defaults' for why and how this module enforces it (the chart has no Helm value for it)."
  type        = number
  default     = 8000

  validation {
    condition     = var.default_gpu_memory >= 0
    error_message = "default_gpu_memory must be >= 0 (0 disables the override, giving the whole physical GPU)."
  }
}

# ─── Scheduling / Placement ───────────────────────────────────────────────────

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

variable "scheduler_leader_elect" {
  description = "Enable HAMi scheduler leader election (scheduler.leaderElect). false avoids an anti-affinity deadlock the chart adds when true, which is fatal to rolling updates on a single-node system pool. See README.md for details."
  type        = bool
  default     = false
}

# ─── Runtime / GPU Operator Integration ───────────────────────────────────────
# See README.md for why these must be the specific values they are (a legacy,
# non-CDI RuntimeClass; the GPU Operator's containerized driver path).

variable "runtime_class_name" {
  description = "Container RuntimeClass the devicePlugin pod runs under, and that HAMi's scheduler injects into GPU workload pods. Must be a legacy (non-CDI) NVIDIA runtime — see README.md 'Notes'."
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

# ─── Cluster Auth ─────────────────────────────────────────────────────────────
# Used to restart hami-scheduler after every hami-scheduler-device ConfigMap
# patch (see default_gpu_memory and main.tf) — always required, since even
# resetting default_gpu_memory to 0 needs the scheduler restarted to take
# effect. Pass local.k8s_auth.* from the root module.

variable "k8s_host" {
  description = "Kubernetes API server URL."
  type        = string

  validation {
    condition     = var.k8s_host != ""
    error_message = "k8s_host must be set (needed to restart hami-scheduler after patching its config) — pass local.k8s_auth.host from the root module."
  }
}

variable "k8s_token" {
  description = "Kubernetes API bearer token."
  type        = string
  sensitive   = true

  validation {
    condition     = var.k8s_token != ""
    error_message = "k8s_token must be set (needed to restart hami-scheduler after patching its config) — pass local.k8s_auth.token from the root module."
  }
}

variable "k8s_cluster_ca_certificate" {
  description = "Base64-decoded cluster CA certificate (PEM)."
  type        = string
  sensitive   = true

  validation {
    condition     = var.k8s_cluster_ca_certificate != ""
    error_message = "k8s_cluster_ca_certificate must be set (needed to restart hami-scheduler after patching its config) — pass local.k8s_auth.cluster_ca_certificate from the root module."
  }
}
