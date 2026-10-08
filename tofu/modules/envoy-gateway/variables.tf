variable "namespace" {
  description = "Kubernetes namespace for the Envoy Gateway controller and the Envoy proxies it provisions"
  type        = string
  default     = "envoy-gateway-system"
}

variable "chart_version" {
  description = "Version of the envoyproxy/gateway-helm chart (format: 'vX.Y.Z')"
  type        = string
  default     = "v1.9.2"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'vX.Y.Z' (e.g. 'v1.9.2')."
  }
}

variable "gateway_class_name" {
  description = "Name of the GatewayClass to create. KServe's built-in Gateway (createGateway = true) references a class named 'envoy'."
  type        = string
  default     = "envoy"
}

variable "service_type" {
  description = "Service type of the Envoy proxy fronting each Gateway. ClusterIP keeps the gateway private (reach it with kubectl port-forward); LoadBalancer provisions a public Linode NodeBalancer (~$10/month) with no authentication in front of it."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "LoadBalancer", "NodePort"], var.service_type)
    error_message = "service_type must be one of ClusterIP, LoadBalancer or NodePort."
  }
}

variable "node_selector" {
  description = "nodeSelector for the Envoy Gateway controller, its certgen job and the Envoy proxy pods. Empty schedules anywhere."
  type        = map(string)
  default     = {}
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
