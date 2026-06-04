variable "manifests_version" {
  description = "Git tag of kubeflow/manifests to install. Accepts the legacy semver format 'vX.Y.Z' (e.g. 'v1.10.0') and the new CalVer format 'YY.MM[.patch]' (e.g. '26.03'). See https://github.com/kubeflow/manifests/releases."
  type        = string
  default     = "26.03"

  validation {
    condition     = can(regex("^(v[0-9]+\\.[0-9]+\\.[0-9]+|[0-9]{2}\\.[0-9]{2}(\\.[0-9]+)?)$", var.manifests_version))
    error_message = "manifests_version must be 'vX.Y.Z' (e.g. 'v1.10.0') or CalVer 'YY.MM[.patch]' (e.g. '26.03')."
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

variable "gpu_toleration_key" {
  description = "Taint key to tolerate on GPU nodes (e.g. 'nvidia.com/gpu'). When non-empty, a kustomize strategic-merge patch is applied to every Deployment and StatefulSet rendered by the manifest build (across all namespaces) so those workloads can schedule onto tainted GPU nodes. Set to empty string to disable."
  type        = string
  default     = "nvidia.com/gpu"
}
