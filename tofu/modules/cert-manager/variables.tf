variable "namespace" {
  description = "Kubernetes namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "chart_version" {
  description = "Version of the jetstack/cert-manager Helm chart (format: 'vX.Y.Z')"
  type        = string
  default     = "v1.21.2"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'vX.Y.Z' (e.g. 'v1.21.2')."
  }
}

variable "node_selector" {
  description = "nodeSelector applied to every cert-manager pod (controller, webhook, cainjector, startup check). Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "enable_service_monitor" {
  description = "Create a Prometheus ServiceMonitor for the cert-manager controller (requires the Prometheus Operator CRDs, i.e. kube-prometheus-stack)."
  type        = bool
  default     = false
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
