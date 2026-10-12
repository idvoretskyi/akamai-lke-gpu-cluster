# The few settings people actually change. Everything else (chart versions,
# CIDRs, sizes, tags) is an opinionated default in locals.tf.
#
# Put your values in tofu/tofu.auto.tfvars (copy tofu.auto.tfvars.example):
# OpenTofu loads *.auto.tfvars automatically, so a plain `tofu apply` works.

# ─── Cluster ──────────────────────────────────────────────────────────────────

variable "cluster_name_prefix" {
  description = "Prefix for the LKE cluster name (defaults to your system username when empty)"
  type        = string
  default     = ""
}

variable "region" {
  description = "Linode region. RTX 4000 Ada GPU plans (g2-gpu-*) are only offered in some regions; de-fra-2 (Frankfurt) and fr-par (Paris) are the EU ones."
  type        = string
  default     = "de-fra-2"

  validation {
    condition     = can(regex("^[a-z]{2,3}-[a-z]{2,10}[0-9]?(-[0-9]+)?$", var.region))
    error_message = "Region must match the Linode slug format (e.g. 'us-ord', 'eu-west', 'de-fra-2')."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the LKE cluster (format: 'X.Y'). LKE retires old versions, so bump this when it does."
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in the format 'X.Y' (e.g. '1.36')."
  }
}

variable "merge_kubeconfig" {
  description = "Merge the cluster's kubeconfig into ~/.kube/config after apply (needs kubectl). Set false in CI or when you manage kubeconfig yourself."
  type        = bool
  default     = true
}

# ─── Nodes ────────────────────────────────────────────────────────────────────
# Both pools are fixed-size (no autoscaling), so cost is predictable.

variable "gpu_node_type" {
  description = "Instance type of the GPU node. The default is the cheapest Linode GPU: NVIDIA RTX 4000 Ada x1 Small, 20 GB (~$0.52/hr)."
  type        = string
  default     = "g2-gpu-rtx4000a1-s"
  # List GPU plans: linode-cli linodes types --json | jq '.[] | select(.class=="gpu")'
}

variable "gpu_node_count" {
  description = "Number of GPU nodes. The model server takes a whole GPU, so extra GPU pods need another node."
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_count >= 1
    error_message = "gpu_node_count must be at least 1."
  }
}

variable "system_node_type" {
  description = "Instance type of the system node, which hosts the whole platform (monitoring, cert-manager, Envoy Gateway, KServe, Argo CD). g6-standard-4 (8 GB, ~$48/month); g6-standard-2 (4 GB) is too small."
  type        = string
  default     = "g6-standard-4"

  validation {
    condition     = var.system_node_type != var.gpu_node_type
    error_message = "system_node_type must differ from gpu_node_type: the two pools are told apart by instance type (local.gpu_pool / local.system_pool), so identical types would make the pool outputs ambiguous."
  }
}

# ─── Access ───────────────────────────────────────────────────────────────────

variable "allowed_kubectl_ips" {
  description = "CIDR ranges allowed to reach the Kubernetes API (port 443). Restrict this to your own IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for ip in var.allowed_kubectl_ips : can(cidrhost(ip, 0))])
    error_message = "Each allowed_kubectl_ips entry must be a valid CIDR (e.g. '203.0.113.10/32', '0.0.0.0/0')."
  }
}

variable "gateway_service_type" {
  description = "Service type of the Envoy proxy behind the model Gateway. ClusterIP (default) keeps the unauthenticated model endpoint private, reached with kubectl port-forward. LoadBalancer exposes it publicly through a Linode NodeBalancer (~$10/month)."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "LoadBalancer"], var.gateway_service_type)
    error_message = "gateway_service_type must be ClusterIP or LoadBalancer."
  }
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana (reached with kubectl port-forward). Change it."
  type        = string
  default     = "admin"
  sensitive   = true
}

# ─── GitOps ───────────────────────────────────────────────────────────────────

variable "gitops_repo_url" {
  description = "Git repository Argo CD syncs the model from. Must be readable without credentials (a public repo or fork)."
  type        = string
  default     = "https://github.com/idvoretskyi/akamai-lke-gpu-cluster.git"
}

variable "gitops_target_revision" {
  description = "Branch, tag or commit of gitops_repo_url to sync. Point it at a feature branch to try changes to gitops/ before merging."
  type        = string
  default     = "main"
}

# ─── Storage ──────────────────────────────────────────────────────────────────

variable "monitoring_storage_class" {
  description = "StorageClass for the Prometheus and Grafana volumes. linode-block-storage deletes the Linode volumes with the cluster. Clusters created before the KServe rebuild use linode-block-storage-retain, and a PVC's class is immutable, so set that value to upgrade them in place (see README 'Upgrading an existing cluster')."
  type        = string
  default     = "linode-block-storage"

  validation {
    condition     = contains(["linode-block-storage", "linode-block-storage-retain"], var.monitoring_storage_class)
    error_message = "monitoring_storage_class must be linode-block-storage or linode-block-storage-retain."
  }
}
