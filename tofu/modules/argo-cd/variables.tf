variable "namespace" {
  description = "Kubernetes namespace for Argo CD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Version of the argo/argo-cd Helm chart (format: 'X.Y.Z')"
  type        = string
  default     = "10.10.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '10.10.1')."
  }
}

variable "node_selector" {
  description = "nodeSelector for every Argo CD component. Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "enable_service_monitor" {
  description = "Expose metrics and create Prometheus ServiceMonitors for the Argo CD components (requires the Prometheus Operator CRDs, i.e. kube-prometheus-stack)."
  type        = bool
  default     = false
}

variable "applications" {
  description = "Bootstrap Argo CD Applications, each syncing one directory of a Git repository into a namespace (created if missing) with automated prune and self-heal."
  type = list(object({
    name            = string
    namespace       = string
    repo_url        = string
    target_revision = optional(string, "HEAD")
    path            = string
  }))
  default = []

  validation {
    condition     = alltrue([for a in var.applications : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", a.name))])
    error_message = "Each application name must be a valid Kubernetes resource name (lowercase alphanumerics and '-')."
  }

  validation {
    condition     = length(distinct([for a in var.applications : a.name])) == length(var.applications)
    error_message = "Application names must be unique: they all become Application objects in the Argo CD namespace."
  }
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
