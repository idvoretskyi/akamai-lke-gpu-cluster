# ─── Cluster ──────────────────────────────────────────────────────────────────

variable "cluster_name_prefix" {
  description = "Prefix for the LKE cluster name (defaults to system username when empty)"
  type        = string
  default     = ""
}

variable "region" {
  description = "Linode region for the cluster (e.g. 'us-ord')"
  type        = string
  default     = "us-ord" # Chicago, US

  validation {
    condition     = can(cidrhost("${var.region}/32", 0)) == false && can(regex("^[a-z]{2,3}-[a-z]{2,4}[0-9]?$", var.region))
    error_message = "Region must match the Linode slug format (e.g. 'us-ord', 'eu-west', 'ap-southeast')."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the LKE cluster (format: 'X.Y')"
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in the format 'X.Y' (e.g. '1.35')."
  }
}

variable "ha_control_plane" {
  description = "Enable high availability for the control plane (~$60/month extra)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to Linode resources"
  type        = list(string)
  default     = ["lke", "gpu", "ml", "ai"]
}

# ─── Node Pool ────────────────────────────────────────────────────────────────
# Autoscaling is disabled. Both pools run a fixed node count to keep costs
# fully predictable and eliminate surprise scale-up charges on GPU nodes.

variable "gpu_node_type" {
  description = "Linode instance type for GPU nodes. Default is the cheapest available GPU plan: NVIDIA RTX 4000 Ada x1 Small (~$0.52/hr, ~$380/mo)."
  type        = string
  default     = "g2-gpu-rtx4000a1-s" # Cheapest Linode GPU — RTX 4000 Ada x1 Small
  # List available GPU plans: linode-cli linodes types --json | jq '.[] | select(.class=="gpu")'
}

variable "gpu_node_count" {
  description = "Number of GPU nodes in the cluster. Autoscaling is disabled; this is the fixed node count."
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_count >= 1
    error_message = "gpu_node_count must be at least 1."
  }
}

# ─── System Node Pool ─────────────────────────────────────────────────────────
# A small, dedicated CPU node pool that hosts the cluster's "system" workloads
# (monitoring stack, metrics-server, OpenCost, GPU Operator controller). Keeping
# these off the GPU nodes means the expensive GPU is reserved purely for
# GPU-intensive workloads, improving utilization and cost-efficiency.

variable "system_node_type" {
  description = "Linode instance type for the dedicated system node pool. g6-standard-2 (2 vCPU, 4 GB, ~$24/month) fits the monitoring stack and GPU Operator controller for a lab cluster. Use g6-standard-8 if adding Kubeflow (the monitoring stack + Kubeflow system pods measure ~9-10 GB in practice, exceeding smaller pools)."
  type        = string
  default     = "g6-standard-2"

  validation {
    condition     = var.system_node_type != var.gpu_node_type
    error_message = "system_node_type must differ from gpu_node_type. The two pools are distinguished by instance type (cost and pool-id outputs match pools via one([... if p.type == var.*_node_type])), so identical types would make those outputs ambiguous and fail."
  }
}

variable "system_node_count" {
  description = "Number of nodes in the system pool. Autoscaling is disabled; this is the fixed node count."
  type        = number
  default     = 1

  validation {
    condition     = var.system_node_count >= 1
    error_message = "system_node_count must be at least 1."
  }
}

variable "dedicate_gpu_nodes" {
  description = "Taint the GPU node pool (nvidia.com/gpu=present:NoSchedule) so only workloads that tolerate the taint (GPU workloads and the GPU Operator's GPU operands) schedule there. System workloads are pinned to the system pool. Set false to allow general workloads back onto GPU nodes."
  type        = bool
  default     = true
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "allowed_kubectl_ips" {
  description = "CIDR ranges allowed to reach the Kubernetes API (port 443)."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for ip in var.allowed_kubectl_ips : can(cidrhost(ip, 0))])
    error_message = "Each allowed_kubectl_ips entry must be a valid CIDR (e.g. '203.0.113.10/32', '0.0.0.0/0')."
  }
}

variable "allowed_monitoring_ips" {
  description = "CIDR ranges allowed to reach monitoring UIs (Grafana, Prometheus)."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for ip in var.allowed_monitoring_ips : can(cidrhost(ip, 0))])
    error_message = "Each allowed_monitoring_ips entry must be a valid CIDR (e.g. '203.0.113.10/32', '0.0.0.0/0')."
  }
}

variable "node_cidrs" {
  description = "Private CIDRs used by LKE nodes and the Linode control plane (used for intra-cluster firewall rules). The default covers the full Linode LKE private node range."
  type        = list(string)
  default     = ["192.168.128.0/17"]

  validation {
    condition     = alltrue([for cidr in var.node_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each node_cidrs entry must be a valid CIDR (e.g. '192.168.128.0/17')."
  }
}

variable "pod_cidrs" {
  description = "Pod network CIDRs assigned by the LKE CNI. The default covers the full Linode LKE pod range."
  type        = list(string)
  default     = ["10.2.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.pod_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each pod_cidrs entry must be a valid CIDR (e.g. '10.2.0.0/16')."
  }
}

# ─── Kubeconfig ──────────────────────────────────────────────────────────────

variable "merge_kubeconfig" {
  description = "Automatically merge the cluster kubeconfig into ~/.kube/config after deployment. Set false in CI or when managing kubeconfig externally."
  type        = bool
  default     = true
}

# ─── GPU Operator ─────────────────────────────────────────────────────────────

variable "install_gpu_operator" {
  description = "Install NVIDIA GPU Operator (automated driver and device plugin management)"
  type        = bool
  default     = true
}

variable "gpu_operator_version" {
  description = "Version of the NVIDIA GPU Operator Helm chart (format: 'vX.Y.Z')"
  type        = string
  default     = "v26.3.2"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gpu_operator_version))
    error_message = "gpu_operator_version must be in the format 'vX.Y.Z' (e.g. 'v26.3.2')."
  }
}

variable "enable_gpu_monitoring" {
  description = "Enable GPU monitoring via DCGM exporter (requires install_gpu_operator = true)"
  type        = bool
  default     = true
}

# ─── HAMi (GPU Virtualization) ────────────────────────────────────────────────
# Lab/experimental: enabled by default since this cluster is destroyed and
# recreated freely (no in-place migration concerns). Replaces the GPU
# Operator's stock device plugin so GPUs can be split into vGPU slices.

variable "install_hami" {
  description = "Install HAMi for GPU virtualization/sharing (splits physical GPUs into schedulable vGPU slices). Disables the GPU Operator's stock device plugin when true. Requires install_gpu_operator = true."
  type        = bool
  default     = true

  validation {
    condition     = !var.install_hami || var.install_gpu_operator
    error_message = "install_hami = true requires install_gpu_operator = true (HAMi relies on the operator's NVIDIA driver and container toolkit)."
  }
}

variable "hami_version" {
  description = "Version of the HAMi Helm chart (format: 'X.Y.Z')"
  type        = string
  default     = "2.9.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.hami_version))
    error_message = "hami_version must be in the format 'X.Y.Z' (e.g. '2.9.0')."
  }
}

variable "hami_device_split_count" {
  description = "Number of vGPU slices each physical GPU is split into by HAMi. E.g. 10 lets up to 10 pods share one physical GPU."
  type        = number
  default     = 10

  validation {
    condition     = var.hami_device_split_count >= 1
    error_message = "hami_device_split_count must be at least 1."
  }
}

variable "hami_default_gpu_memory" {
  description = "vGPU memory (MB) a Pod gets when it requests nvidia.com/gpu without an explicit nvidia.com/gpumem limit. Defaults to a real slice (8000 MB) rather than the whole physical GPU (HAMi's own chart default), since most orchestrators — including Kubeflow Pipelines via the kfp SDK — have no easy way to set that extra resource key. Set to 0 to restore whole-GPU behavior for unslotted requests."
  type        = number
  default     = 8000

  validation {
    condition     = var.hami_default_gpu_memory >= 0
    error_message = "hami_default_gpu_memory must be >= 0 (0 disables the override, giving the whole physical GPU)."
  }
}

# ─── Kubeflow ─────────────────────────────────────────────────────────────────
# Opt-in and heavy (see modules/kubeflow/README.md) — installs via kustomize +
# kubectl apply, not Helm, since upstream Kubeflow has no single full-platform
# Helm chart.

variable "install_kubeflow" {
  description = "Install the full Kubeflow Platform (kubeflow/community-distribution). Heavy — recommend system_node_type = 'g6-standard-8' (32 GB; measured usage is ~9-10 GB) and a generous GPU pool. Opt-in even for a lab cluster."
  type        = bool
  default     = false
}

variable "kubeflow_ref" {
  description = "Git tag/branch of kubeflow/community-distribution to install (e.g. a release tag, or 'master')."
  type        = string
  default     = "master"
}

# ─── Metrics Server ───────────────────────────────────────────────────────────

variable "install_metrics_server" {
  description = "Install Kubernetes Metrics Server (enables kubectl top and HPA)"
  type        = bool
  default     = true
}

# ─── Monitoring Stack ─────────────────────────────────────────────────────────

variable "install_monitoring" {
  description = "Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana."
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period (e.g. '7d', '15d', '30d')."
  type        = string
  default     = "7d"

  validation {
    condition     = can(regex("^[0-9]+(d|h|w|y)$", var.prometheus_retention))
    error_message = "prometheus_retention must be a duration string like '15d', '48h', '4w'."
  }
}

# ─── Storage ──────────────────────────────────────────────────────────────────
# Linode block storage costs ~$0.10/GB/month. Defaults are sized for a
# cost-efficient single-node dev/test cluster.

variable "prometheus_storage_size" {
  description = "Prometheus persistent storage size (e.g. '15Gi'). Linode block storage ~$0.10/GB/month."
  type        = string
  default     = "15Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a Kubernetes quantity like '30Gi'."
  }
}

variable "grafana_storage_size" {
  description = "Grafana persistent storage size (e.g. '5Gi')"
  type        = string
  default     = "5Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.grafana_storage_size))
    error_message = "grafana_storage_size must be a Kubernetes quantity like '5Gi'."
  }
}

# ─── Cost Monitoring (OpenCost) ───────────────────────────────────────────────

variable "install_opencost" {
  description = "Install OpenCost for Kubernetes cost monitoring (requires install_monitoring = true for full functionality)"
  type        = bool
  default     = true
}

variable "opencost_chart_version" {
  description = "Version of the OpenCost Helm chart"
  type        = string
  default     = "2.5.14"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.opencost_chart_version))
    error_message = "opencost_chart_version must be in the format 'X.Y.Z' (e.g. '2.5.14')."
  }
}

# ─── Monitoring Resource Requests ────────────────────────────────────────────

variable "prometheus_resources" {
  description = "CPU/memory requests and limits for the Prometheus pod."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "1000m", memory = "2Gi" }
  }
}

variable "grafana_resources" {
  description = "CPU/memory requests and limits for the Grafana pod."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { cpu = "200m", memory = "512Mi" }
  }
}
