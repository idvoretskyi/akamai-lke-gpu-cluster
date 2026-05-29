variable "namespace" {
  description = "Kubernetes namespace for OpenCost"
  type        = string
  default     = "opencost"
}

variable "opencost_chart_version" {
  description = "Version of the OpenCost Helm chart"
  type        = string
  default     = "2.5.14"
}

variable "prometheus_url" {
  description = "URL of the Prometheus instance OpenCost should scrape (in-cluster service URL)"
  type        = string
  default     = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
}

variable "enable_ui" {
  description = "Enable the OpenCost web UI"
  type        = bool
  default     = true
}

variable "enable_service_monitor" {
  description = "Create a Prometheus ServiceMonitor so kube-prometheus-stack scrapes OpenCost metrics"
  type        = bool
  default     = true
}

variable "resources" {
  description = "CPU and memory resource requests and limits for OpenCost pods"
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
      memory = "100Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "256Mi"
    }
  }
}

variable "node_selector" {
  description = "nodeSelector to pin the OpenCost pod onto a specific node pool (e.g. the system pool). Empty schedules anywhere."
  type        = map(string)
  default     = {}
}

variable "extra_labels" {
  description = "Additional Kubernetes labels to apply to OpenCost workloads and metrics. Useful for cost attribution alongside resource tags."
  type        = map(string)
  default     = {}
}
