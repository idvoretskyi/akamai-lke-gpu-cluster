variable "namespace" {
  description = "Kubernetes namespace for Argo Workflows. Workflows also run here (single-namespace mode)."
  type        = string
  default     = "argo"
}

variable "chart_version" {
  description = "Version of the argo/argo-workflows Helm chart"
  type        = string
  default     = "2.0.11"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '2.0.11')."
  }
}

variable "timeout" {
  description = "Seconds to wait for the Helm release to become ready"
  type        = number
  default     = 600
}

variable "auth_mode" {
  description = "Argo Server auth mode: 'server' (no login; the server's own service account is used — fine for a lab reached only via kubectl port-forward) or 'client' (requires a bearer token from `argo auth token`)."
  type        = string
  default     = "server"

  validation {
    condition     = contains(["server", "client"], var.auth_mode)
    error_message = "auth_mode must be 'server' or 'client'."
  }
}

variable "enable_service_monitor" {
  description = "Create a Prometheus ServiceMonitor for the workflow controller (requires the ServiceMonitor CRD from kube-prometheus-stack)"
  type        = bool
  default     = false
}

variable "node_selector" {
  description = "Node selector for the controller and server pods (the system pool)"
  type        = map(string)
  default     = {}
}

variable "resources" {
  description = "CPU and memory resource requests and limits for the controller and server pods"
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
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "250m"
      memory = "256Mi"
    }
  }
}
