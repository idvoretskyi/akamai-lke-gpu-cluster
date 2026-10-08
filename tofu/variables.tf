# ─── Cluster ──────────────────────────────────────────────────────────────────

variable "cluster_name_prefix" {
  description = "Prefix for the LKE cluster name (defaults to system username when empty)"
  type        = string
  default     = ""
}

variable "region" {
  description = "Linode region for the cluster (e.g. 'de-fra-2'). RTX 4000 Ada GPU plans (g2-gpu-*) are only offered in some regions — see README 'Region and GPU availability'."
  type        = string
  default     = "de-fra-2" # Frankfurt 2, DE — EU region with RTX 4000 Ada, balanced for UK/UA access

  validation {
    condition     = can(regex("^[a-z]{2,3}-[a-z]{2,10}[0-9]?(-[0-9]+)?$", var.region))
    error_message = "Region must match the Linode slug format (e.g. 'us-ord', 'eu-west', 'ap-southeast', 'de-fra-2')."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the LKE cluster (format: 'X.Y')"
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in the format 'X.Y' (e.g. '1.36')."
  }
}

variable "ha_control_plane" {
  description = "Enable high availability for the control plane (~$60/month extra)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to Linode resources"
  type        = list(string)
  default     = ["lke", "gpu", "ml", "ai"]
}

# ─── Node Pool ────────────────────────────────────────────────────────────────
# Autoscaling is disabled. Both pools run a fixed node count to keep costs
# fully predictable and eliminate surprise scale-up charges on GPU nodes.

variable "gpu_node_type" {
  description = "Linode instance type for GPU nodes. Default is the cheapest available GPU plan: NVIDIA RTX 4000 Ada x1 Small (~$0.52/hr, ~$380/mo)."
  type        = string
  default     = "g2-gpu-rtx4000a1-s" # Cheapest Linode GPU — RTX 4000 Ada x1 Small
  # List available GPU plans: linode-cli linodes types --json | jq '.[] | select(.class=="gpu")'
}

variable "gpu_node_count" {
  description = "Number of GPU nodes in the cluster. Autoscaling is disabled; this is the fixed node count."
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_count >= 1
    error_message = "gpu_node_count must be at least 1."
  }
}

# ─── System Node Pool ─────────────────────────────────────────────────────────
# A dedicated CPU node pool that hosts the cluster's "system" workloads
# (monitoring, metrics-server, GPU Operator controller, cert-manager, Envoy
# Gateway, KServe controller, Argo CD). Keeping these off the GPU nodes means
# the expensive GPU is reserved purely for model serving.

variable "system_node_type" {
  description = "Linode instance type for the dedicated system node pool. g6-standard-4 (4 vCPU, 8 GB, ~$48/month) fits the full platform stack; g6-standard-2 (4 GB) is too small once KServe, Envoy Gateway and Argo CD are installed."
  type        = string
  default     = "g6-standard-4"

  validation {
    condition     = var.system_node_type != var.gpu_node_type
    error_message = "system_node_type must differ from gpu_node_type. The two pools are distinguished by instance type (cost and pool-id outputs match pools via local.gpu_pool / local.system_pool, which select by p.type), so identical types would make those outputs ambiguous and fail."
  }
}

variable "system_node_count" {
  description = "Number of nodes in the system pool. Autoscaling is disabled; this is the fixed node count."
  type        = number
  default     = 1

  validation {
    condition     = var.system_node_count >= 1
    error_message = "system_node_count must be at least 1."
  }
}

variable "dedicate_gpu_nodes" {
  description = "Taint the GPU node pool (nvidia.com/gpu=present:NoSchedule) so only workloads that tolerate the taint (GPU workloads and the GPU Operator's GPU operands) schedule there. System workloads are pinned to the system pool. Set false to allow general workloads back onto GPU nodes."
  type        = bool
  default     = true
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "allowed_kubectl_ips" {
  description = "CIDR ranges allowed to reach the Kubernetes API (port 443)."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for ip in var.allowed_kubectl_ips : can(cidrhost(ip, 0))])
    error_message = "Each allowed_kubectl_ips entry must be a valid CIDR (e.g. '203.0.113.10/32', '0.0.0.0/0')."
  }
}

variable "node_cidrs" {
  description = "Private CIDRs used by LKE nodes and the Linode control plane (used for intra-cluster firewall rules). The default covers the full Linode LKE private node range."
  type        = list(string)
  default     = ["192.168.128.0/17"]

  validation {
    condition     = alltrue([for cidr in var.node_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each node_cidrs entry must be a valid CIDR (e.g. '192.168.128.0/17')."
  }
}

variable "pod_cidrs" {
  description = "Pod network CIDRs assigned by the LKE CNI. The default covers the full Linode LKE pod range."
  type        = list(string)
  default     = ["10.2.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.pod_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each pod_cidrs entry must be a valid CIDR (e.g. '10.2.0.0/16')."
  }
}

# ─── Kubeconfig ──────────────────────────────────────────────────────────────

variable "merge_kubeconfig" {
  description = "Automatically merge the cluster kubeconfig into ~/.kube/config after deployment. Set false in CI or when managing kubeconfig externally."
  type        = bool
  default     = true
}

# ─── GPU Operator ─────────────────────────────────────────────────────────────

variable "install_gpu_operator" {
  description = "Install NVIDIA GPU Operator (automated driver and device plugin management)"
  type        = bool
  default     = true
}

variable "gpu_operator_version" {
  description = "Version of the NVIDIA GPU Operator Helm chart (format: 'vX.Y.Z')"
  type        = string
  default     = "v26.7.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gpu_operator_version))
    error_message = "gpu_operator_version must be in the format 'vX.Y.Z' (e.g. 'v26.7.1')."
  }
}

variable "gpu_operator_install_toolkit" {
  description = "Let the GPU Operator install the NVIDIA Container Toolkit on GPU nodes. Keep false on LKE: the GPU node image ships the driver, toolkit and a containerd 'nvidia' runtime, and the operator's toolkit rewriting that config leaves containerd unable to restart (node goes NotReady)."
  type        = bool
  default     = false
}

variable "enable_gpu_monitoring" {
  description = "Enable GPU monitoring via DCGM exporter (requires install_gpu_operator = true)"
  type        = bool
  default     = true
}

# ─── Metrics Server ───────────────────────────────────────────────────────────

variable "install_metrics_server" {
  description = "Install Kubernetes Metrics Server (enables kubectl top and HPA)"
  type        = bool
  default     = true
}

variable "metrics_server_version" {
  description = "Version of the Metrics Server Helm chart"
  type        = string
  default     = "3.12.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.metrics_server_version))
    error_message = "metrics_server_version must be in the format 'X.Y.Z' (e.g. '3.12.2')."
  }
}

# ─── Monitoring Stack ─────────────────────────────────────────────────────────

variable "install_monitoring" {
  description = "Install kube-prometheus-stack (Prometheus + Grafana + node-exporter + kube-state-metrics; Alertmanager is disabled)"
  type        = bool
  default     = true
}

variable "kube_prometheus_stack_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "80.8.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kube_prometheus_stack_version))
    error_message = "kube_prometheus_stack_version must be in the format 'X.Y.Z' (e.g. '80.8.0')."
  }
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana."
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period (e.g. '7d', '15d', '30d')."
  type        = string
  default     = "7d"

  validation {
    condition     = can(regex("^[0-9]+(d|h|w|y)$", var.prometheus_retention))
    error_message = "prometheus_retention must be a duration string like '15d', '48h', '4w'."
  }
}

# ─── Storage ──────────────────────────────────────────────────────────────────
# Linode block storage costs ~$0.10/GB/month. Defaults are sized for a
# cost-efficient single-node dev/test cluster.

variable "prometheus_storage_size" {
  description = "Prometheus persistent storage size (e.g. '15Gi'). Linode block storage ~$0.10/GB/month."
  type        = string
  default     = "15Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a Kubernetes quantity like '30Gi'."
  }
}

variable "grafana_storage_size" {
  description = "Grafana persistent storage size (e.g. '5Gi')"
  type        = string
  default     = "5Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.grafana_storage_size))
    error_message = "grafana_storage_size must be a Kubernetes quantity like '5Gi'."
  }
}

# ─── Model Serving (KServe + vLLM) ────────────────────────────────────────────
# install_kserve also installs its dependencies: cert-manager (webhook TLS) and
# Envoy Gateway (Gateway API implementation).

variable "install_kserve" {
  description = "Install KServe (Standard mode, Gateway API) with its dependencies cert-manager and Envoy Gateway, plus the vLLM-backed Hugging Face serving runtime. Requires install_gpu_operator = true to serve on the GPU."
  type        = bool
  default     = true
}

variable "kserve_version" {
  description = "KServe version for its kserve-crd, kserve-resources and kserve-runtime-configs Helm charts (format: 'vX.Y.Z'). Keep the image tag in gitops/vllm/inferenceservice.yaml (kserve/huggingfaceserver:<version>-gpu) in step."
  type        = string
  default     = "v0.20.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kserve_version))
    error_message = "kserve_version must be in the format 'vX.Y.Z' (e.g. 'v0.20.0')."
  }
}

variable "kserve_ingress_domain" {
  description = "Domain for InferenceService hostnames (<name>-<namespace>.<domain>). The Gateway routes on the Host header, so clients without matching DNS set it explicitly."
  type        = string
  default     = "kserve.local"
}

variable "cert_manager_version" {
  description = "Version of the jetstack/cert-manager Helm chart (format: 'vX.Y.Z')"
  type        = string
  default     = "v1.21.2"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.cert_manager_version))
    error_message = "cert_manager_version must be in the format 'vX.Y.Z' (e.g. 'v1.21.2')."
  }
}

variable "envoy_gateway_version" {
  description = "Version of the envoyproxy/gateway-helm chart (format: 'vX.Y.Z')"
  type        = string
  default     = "v1.9.2"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.envoy_gateway_version))
    error_message = "envoy_gateway_version must be in the format 'vX.Y.Z' (e.g. 'v1.9.2')."
  }
}

variable "gateway_service_type" {
  description = "Service type of the Envoy proxy behind KServe's Gateway. ClusterIP (default) keeps the unauthenticated model endpoint private, reached with kubectl port-forward. LoadBalancer exposes it publicly through a Linode NodeBalancer (~$10/month)."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "LoadBalancer"], var.gateway_service_type)
    error_message = "gateway_service_type must be ClusterIP or LoadBalancer."
  }
}

variable "model_namespace" {
  description = "Namespace the GitOps-managed InferenceService is deployed into (created by Argo CD). Must not be the KServe control-plane namespace."
  type        = string
  default     = "vllm"

  validation {
    condition     = var.model_namespace != "kserve"
    error_message = "model_namespace must not be 'kserve': KServe's webhooks skip its control-plane namespace."
  }
}

# ─── GitOps (Argo CD) ─────────────────────────────────────────────────────────

variable "install_argo_cd" {
  description = "Install Argo CD. With install_kserve it bootstraps the 'vllm' Application, which syncs the InferenceService from gitops_path in gitops_repo_url."
  type        = bool
  default     = true
}

variable "argo_cd_version" {
  description = "Version of the argo/argo-cd Helm chart (format: 'X.Y.Z')"
  type        = string
  default     = "10.10.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argo_cd_version))
    error_message = "argo_cd_version must be in the format 'X.Y.Z' (e.g. '10.10.1')."
  }
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD syncs the model workloads from. Must be readable without credentials (a public repo or fork)."
  type        = string
  default     = "https://github.com/idvoretskyi/akamai-lke-gpu-cluster.git"
}

variable "gitops_target_revision" {
  description = "Branch, tag or commit of gitops_repo_url to sync. Point it at a feature branch to test changes to gitops/ before merging."
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Directory in gitops_repo_url holding the model workloads (a Kustomize directory). Empty skips the bootstrap Application."
  type        = string
  default     = "gitops/vllm"
}

# ─── Monitoring Resource Requests ────────────────────────────────────────────

variable "prometheus_resources" {
  description = "CPU/memory requests and limits for the Prometheus pod."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "1000m", memory = "2Gi" }
  }
}

variable "grafana_resources" {
  description = "CPU/memory requests and limits for the Grafana pod."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { cpu = "200m", memory = "512Mi" }
  }
}
