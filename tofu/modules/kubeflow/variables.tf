variable "manifests_version" {
  description = "Git tag of kubeflow/manifests to install (format 'vX.Y.Z'). See https://github.com/kubeflow/manifests/releases."
  type        = string
  default     = "v1.10.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.manifests_version))
    error_message = "manifests_version must be in the format 'vX.Y.Z' (e.g. 'v1.10.0')."
  }
}

variable "kubeconfig_b64" {
  description = "Base64-encoded kubeconfig for the target cluster (from the LKE cluster resource). Written to a temporary file for the install; never persisted to disk by the module."
  type        = string
  sensitive   = true
}

variable "cluster_id" {
  description = "LKE cluster ID. Used as a trigger so Kubeflow is re-applied if the cluster is recreated."
  type        = string
}
