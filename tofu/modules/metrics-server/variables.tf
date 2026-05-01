variable "namespace" {
  description = "Kubernetes namespace for Metrics Server"
  type        = string
  default     = "kube-system"
}

variable "metrics_server_version" {
  description = "Version of the Metrics Server Helm chart"
  type        = string
  default     = "3.12.2"
}

variable "replicas" {
  description = "Number of Metrics Server replicas (2 recommended for high availability)"
  type        = number
  default     = 2

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
