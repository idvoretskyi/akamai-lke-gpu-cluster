# ─── Cluster ──────────────────────────────────────────────────────────────────

output "cluster_id" {
  description = "The ID of the LKE cluster"
  value       = linode_lke_cluster.gpu_cluster.id
}

output "cluster_label" {
  description = "The label of the LKE cluster"
  value       = linode_lke_cluster.gpu_cluster.label
}

output "cluster_region" {
  description = "The region where the cluster is deployed"
  value       = linode_lke_cluster.gpu_cluster.region
}

output "kubernetes_version" {
  description = "The Kubernetes version running on the cluster"
  value       = linode_lke_cluster.gpu_cluster.k8s_version
}

output "api_endpoints" {
  description = "The API endpoints for the cluster"
  value       = linode_lke_cluster.gpu_cluster.api_endpoints
}

output "kubectl_context" {
  description = "The kubectl context name for this cluster"
  value       = "lke${linode_lke_cluster.gpu_cluster.id}-ctx"
}

output "cluster_dashboard_url" {
  description = "URL to the Linode cluster dashboard"
  value       = linode_lke_cluster.gpu_cluster.dashboard_url
}

# ─── Node Pools ───────────────────────────────────────────────────────────────
# Pools are matched by instance type rather than list index, since the order of
# the pool blocks is not guaranteed to be stable in state.

output "gpu_node_pool_id" {
  description = "The ID of the GPU node pool"
  value       = local.gpu_pool.id
}

output "gpu_node_pool_count" {
  description = "Number of nodes in the GPU pool"
  value       = local.gpu_pool.count
}

output "system_node_pool_id" {
  description = "The ID of the dedicated system node pool"
  value       = local.system_pool.id
}

output "system_node_pool_count" {
  description = "Number of nodes in the system pool"
  value       = local.system_pool.count
}

# ─── Networking ───────────────────────────────────────────────────────────────

output "firewall_id" {
  description = "The ID of the firewall protecting the cluster"
  value       = linode_firewall.lke_firewall.id
}

# ─── Kubeconfig ──────────────────────────────────────────────────────────────

output "kubeconfig_path" {
  description = "Path to the merged kubeconfig file (when merge_kubeconfig = true)"
  value       = var.merge_kubeconfig ? "~/.kube/config (merged)" : "kubeconfig merge disabled — manage kubeconfig externally"
}

# ─── What to do next ──────────────────────────────────────────────────────────

output "next_steps" {
  description = "How to use the cluster"
  value       = <<-EOT
    Context:  lke${linode_lke_cluster.gpu_cluster.id}-ctx  (kubectl config use-context ...)

    The model (${local.inference_service}) is deployed by Argo CD from ${var.gitops_repo_url}
    (${local.gitops_path} @ ${var.gitops_target_revision}). Its first start pulls ~7 GB of
    image and ~9 GB of weights, so allow ~10 minutes after apply.

    scripts/status.sh          # is everything healthy?
    scripts/chat.sh "Hello"    # ask the model a question
    scripts/ui.sh argocd       # Argo CD UI on http://localhost:8081 (prints the password)
    scripts/ui.sh grafana      # Grafana on http://localhost:3000 (user admin)
    scripts/ui.sh prometheus   # Prometheus on http://localhost:9090
    scripts/gpu-test.sh        # raw nvidia-smi; needs the GPU free (see README)
  EOT
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

output "grafana_admin_password" {
  description = "Grafana admin password"
  sensitive   = true
  value       = var.grafana_admin_password
}
