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

variable "default_gpu_memory" {
  description = "vGPU memory (MB) a Pod gets when it requests nvidia.com/gpu WITHOUT an explicit nvidia.com/gpumem limit (HAMi scheduler-config nvidia.defaultMemory). 0 (chart default) means such a Pod gets the whole physical GPU, which defeats virtualization for workloads that have no easy way to set that extra resource key (e.g. Kubeflow Pipelines components via the kfp SDK, which only supports one accelerator resource type). HAMi v2.9.0's chart hardcodes this value with no Helm knob for it, so this module patches the hami-scheduler-device ConfigMap directly after each Helm apply — see main.tf for details. Set to 0 to disable (chart default, whole-GPU behavior)."
  type        = number
  default     = 8000

  validation {
    condition     = var.default_gpu_memory >= 0
    error_message = "default_gpu_memory must be >= 0 (0 disables the override)."
  }
}

variable "k8s_host" {
  description = "Kubernetes API server URL. Only used (to build a scratch kubeconfig for a `kubectl rollout restart`) when default_gpu_memory > 0 — the ConfigMap patch above requires a scheduler restart to take effect, since HAMi only reads it at startup."
  type        = string
  default     = ""

  validation {
    condition     = var.default_gpu_memory == 0 || var.k8s_host != ""
    error_message = "k8s_host must be set when default_gpu_memory > 0 (needed to restart hami-scheduler after patching its config) — pass local.k8s_auth.host from the root module."
  }
}

variable "k8s_token" {
  description = "Kubernetes API bearer token. See k8s_host."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.default_gpu_memory == 0 || var.k8s_token != ""
    error_message = "k8s_token must be set when default_gpu_memory > 0 (needed to restart hami-scheduler after patching its config) — pass local.k8s_auth.token from the root module."
  }
}

variable "k8s_cluster_ca_certificate" {
  description = "Base64-decoded cluster CA certificate (PEM). See k8s_host."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.default_gpu_memory == 0 || var.k8s_cluster_ca_certificate != ""
    error_message = "k8s_cluster_ca_certificate must be set when default_gpu_memory > 0 (needed to restart hami-scheduler after patching its config) — pass local.k8s_auth.cluster_ca_certificate from the root module."
  }
}
