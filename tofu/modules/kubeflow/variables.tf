variable "kubeflow_ref" {
  description = "Git tag/branch of kubeflow/community-distribution to install (e.g. a release tag like 'v1.11.0', or 'master' for the latest, less stable, distribution)."
  type        = string
  default     = "master"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.kubeflow_ref))
    error_message = "kubeflow_ref must be a valid git ref (branch/tag) using only letters, digits, '.', '_', '/', '-'."
  }
}

variable "k8s_host" {
  description = "Kubernetes API server URL (from the LKE cluster kubeconfig)."
  type        = string
}

variable "k8s_token" {
  description = "Kubernetes API bearer token (from the LKE cluster kubeconfig)."
  type        = string
  sensitive   = true
}

variable "k8s_cluster_ca_certificate" {
  description = "Base64-decoded cluster CA certificate (PEM) for the Kubernetes API server."
  type        = string
  sensitive   = true
}

variable "install_timeout" {
  description = "Timeout (seconds) for EACH kubectl apply attempt inside the install script's retry loop (up to 15 attempts, 20s apart) — not a cap on the total install time, which can therefore run considerably longer than this value across all retries."
  type        = number
  default     = 1800
}
