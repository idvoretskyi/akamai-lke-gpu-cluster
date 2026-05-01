variable "namespace" {
  description = "Kubernetes namespace for the monitoring stack"
  type        = string
  default     = "monitoring"
}

variable "kube_prometheus_stack_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "80.8.0"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period (e.g. '15d')"
  type        = string
  default     = "15d"
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent storage size (e.g. '50Gi')"
  type        = string
  default     = "50Gi"
}

variable "alertmanager_storage_size" {
  description = "Alertmanager persistent storage size (e.g. '10Gi')"
  type        = string
  default     = "10Gi"
}

variable "grafana_storage_size" {
  description = "Grafana persistent storage size (e.g. '10Gi')"
  type        = string
  default     = "10Gi"
}

variable "storage_class" {
  description = "Kubernetes StorageClass used for persistent volumes (Prometheus, Grafana, Alertmanager)"
  type        = string
  default     = "linode-block-storage-retain"
}

variable "enable_gpu_monitoring" {
  description = "Enable GPU monitoring via DCGM exporter (requires GPU Operator with DCGM enabled)"
  type        = bool
  default     = false
}
