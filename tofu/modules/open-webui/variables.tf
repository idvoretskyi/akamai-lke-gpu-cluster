variable "namespace" {
  description = "Kubernetes namespace for Open WebUI"
  type        = string
  default     = "open-webui"
}

variable "chart_version" {
  description = "Version of the open-webui/open-webui Helm chart"
  type        = string
  default     = "16.6.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be in the format 'X.Y.Z' (e.g. '16.6.0')."
  }
}

variable "timeout" {
  description = "Seconds to wait for the Helm release to become ready"
  type        = number
  default     = 600
}

variable "ollama_url" {
  description = "In-cluster URL of the Ollama API the UI should use"
  type        = string
  default     = "http://ollama.ollama.svc.cluster.local:11434"
}

variable "storage_size" {
  description = "Size of the PVC holding Open WebUI's data (accounts, chats, settings)"
  type        = string
  default     = "5Gi"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.storage_size))
    error_message = "storage_size must be a quantity in Gi or Ti (e.g. '5Gi')."
  }
}

variable "storage_class" {
  description = "Storage class of the data PVC. The Delete class means destroying the cluster also removes the volume, so it is not billed after teardown."
  type        = string
  default     = "linode-block-storage"
}

variable "enable_signup" {
  description = "Allow new users to sign up. The first account created becomes the admin, so leave this on only while the UI is reachable only through kubectl port-forward. Set it to false after creating the admin account."
  type        = bool
  default     = true
}

variable "node_selector" {
  description = "Node selector for the Open WebUI pod (the system pool)"
  type        = map(string)
  default     = {}
}

variable "resources" {
  description = "CPU and memory resource requests and limits for the Open WebUI pod"
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
      memory = "512Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }
}
