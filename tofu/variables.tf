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
  default     = "1.34"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in the format 'X.Y' (e.g. '1.34')."
  }
}

variable "ha_control_plane" {
  description = "Enable high availability for the control plane (~$60/month extra). Set true for production; false to minimize cost."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to Linode resources"
  type        = list(string)
  default     = ["lke", "gpu", "ml", "ai"]
}

# ─── Node Pool & Autoscaling ──────────────────────────────────────────────────

variable "gpu_node_type" {
  description = "Linode instance type for GPU nodes. Default is the cheapest available GPU plan: NVIDIA RTX 4000 Ada x1 Small (~$0.52/hr, ~$380/mo)."
  type        = string
  default     = "g2-gpu-rtx4000a1-s" # Cheapest Linode GPU — RTX 4000 Ada x1 Small
  # List available GPU plans: linode-cli linodes types --json | jq '.[] | select(.class=="gpu")'
}

variable "gpu_node_count" {
  description = "Initial number of GPU nodes in the cluster (must be within autoscaler_min..autoscaler_max)"
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_count >= 1
    error_message = "gpu_node_count must be at least 1."
  }

  validation {
    condition     = var.gpu_node_count >= var.autoscaler_min
    error_message = "gpu_node_count must be >= autoscaler_min (${var.autoscaler_min})."
  }

  validation {
    condition     = var.gpu_node_count <= var.autoscaler_max
    error_message = "gpu_node_count must be <= autoscaler_max (${var.autoscaler_max})."
  }
}

variable "autoscaler_min" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1

  validation {
    condition     = var.autoscaler_min >= 1
    error_message = "autoscaler_min must be at least 1."
  }
}

variable "autoscaler_max" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 5

  validation {
    condition     = var.autoscaler_max >= var.autoscaler_min
    error_message = "autoscaler_max must be >= autoscaler_min (${var.autoscaler_min})."
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "allowed_kubectl_ips" {
  description = "CIDR ranges allowed to reach the Kubernetes API (port 443). Restrict in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for ip in var.allowed_kubectl_ips : can(cidrhost(ip, 0))])
    error_message = "Each allowed_kubectl_ips entry must be a valid CIDR (e.g. '203.0.113.10/32', '0.0.0.0/0')."
  }
}

variable "allowed_monitoring_ips" {
  description = "CIDR ranges allowed to reach monitoring UIs (Grafana, Prometheus). Restrict in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for ip in var.allowed_monitoring_ips : can(cidrhost(ip, 0))])
    error_message = "Each allowed_monitoring_ips entry must be a valid CIDR (e.g. '203.0.113.10/32', '0.0.0.0/0')."
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
  default     = "v24.9.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gpu_operator_version))
    error_message = "gpu_operator_version must be in the format 'vX.Y.Z' (e.g. 'v24.9.0')."
  }
}

variable "enable_gpu_monitoring" {
  description = "Enable GPU monitoring via DCGM exporter (requires install_gpu_operator = true)"
  type        = bool
  default     = true
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
  description = "Admin password for Grafana (use a strong password in production)"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period (e.g. '15d', '30d')"
  type        = string
  default     = "15d"

  validation {
    condition     = can(regex("^[0-9]+(d|h|w|y)$", var.prometheus_retention))
    error_message = "prometheus_retention must be a duration string like '15d', '48h', '4w'."
  }
}

# ─── Storage ──────────────────────────────────────────────────────────────────
# Linode block storage costs ~$0.10/GB/month. Defaults are sized for a
# cost-efficient single-node dev/test cluster.

variable "prometheus_storage_size" {
  description = "Prometheus persistent storage size (e.g. '30Gi'). ~$3/month per 30Gi on Linode block storage."
  type        = string
  default     = "30Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a Kubernetes quantity like '30Gi'."
  }
}

variable "alertmanager_storage_size" {
  description = "Alertmanager persistent storage size (e.g. '5Gi')"
  type        = string
  default     = "5Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.alertmanager_storage_size))
    error_message = "alertmanager_storage_size must be a Kubernetes quantity like '5Gi'."
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
