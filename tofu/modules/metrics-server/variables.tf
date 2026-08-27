variable "namespace" {
  description = "Kubernetes namespace for Metrics Server"
  type        = string
  default     = "kube-system"
}

variable "metrics_server_version" {
  description = "Version of the Metrics Server Helm chart"
  type        = string
  default     = "3.12.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.metrics_server_version))
    error_message = "metrics_server_version must be in the format 'X.Y.Z' (e.g. '3.12.2')."
  }
}

variable "node_selector" {
  description = "nodeSelector to pin Metrics Server pods onto a specific node pool (e.g. the system pool). Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "replicas" {
  description = "Number of Metrics Server replicas. Default 1 suits single-node clusters; set to 2 for multi-node HA deployments."
  type        = number
  default     = 1

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "resources" {
  description = "CPU and memory resource requests and limits for Metrics Server pods"
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
    requests = {
      cpu    = "100m"
      memory = "200Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "400Mi"
    }
  }
}
