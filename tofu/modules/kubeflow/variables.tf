variable "kubeflow_ref" {
  description = "Git tag/branch of kubeflow/community-distribution to install (e.g. a release tag like 'v1.11.0', or 'master' for the latest, less stable, distribution)."
  type        = string
  default     = "master"
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
  description = "Timeout (seconds) for the full Kubeflow install script (it retries kubectl apply until all CRDs/resources settle)."
  type        = number
  default     = 1800
}
