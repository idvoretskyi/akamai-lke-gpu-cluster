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
  description = "The ID of the GPU node pool (use with scripts/suspend-cluster.sh)"
  value       = one([for p in linode_lke_cluster.gpu_cluster.pool : p.id if p.type == var.gpu_node_type])
}

output "gpu_node_pool_count" {
  description = "Number of nodes in the GPU pool"
  value       = one([for p in linode_lke_cluster.gpu_cluster.pool : p.count if p.type == var.gpu_node_type])
}

output "system_node_pool_id" {
  description = "The ID of the dedicated system node pool"
  value       = one([for p in linode_lke_cluster.gpu_cluster.pool : p.id if p.type == var.system_node_type])
}

output "system_node_pool_count" {
  description = "Number of nodes in the system pool"
  value       = one([for p in linode_lke_cluster.gpu_cluster.pool : p.count if p.type == var.system_node_type])
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

# ─── GPU Operator ─────────────────────────────────────────────────────────────

output "gpu_operator_namespace" {
  description = "GPU Operator namespace (null when not installed)"
  value       = try(module.gpu_operator[0].namespace, null)
}

output "gpu_operator_version" {
  description = "GPU Operator chart version (null when not installed)"
  value       = try(module.gpu_operator[0].version, null)
}

output "gpu_operator_status" {
  description = "GPU Operator Helm release status (null when not installed)"
  value       = try(module.gpu_operator[0].status, null)
}

output "gpu_validation_commands" {
  description = "Commands to validate GPU setup (null when GPU Operator is not installed)"
  value       = try(module.gpu_operator[0].validation_commands, null)
}

# ─── Metrics Server ───────────────────────────────────────────────────────────

output "metrics_server_namespace" {
  description = "Metrics Server namespace (null when not installed)"
  value       = try(module.metrics_server[0].namespace, null)
}

output "metrics_server_version" {
  description = "Metrics Server chart version (null when not installed)"
  value       = try(module.metrics_server[0].version, null)
}

output "metrics_server_validation_commands" {
  description = "Commands to validate Metrics Server (null when not installed)"
  value       = try(module.metrics_server[0].validation_commands, null)
}

# ─── Monitoring Stack ─────────────────────────────────────────────────────────

output "monitoring_namespace" {
  description = "Monitoring stack namespace (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].namespace, null)
}

output "monitoring_version" {
  description = "kube-prometheus-stack chart version (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].version, null)
}

output "grafana_service" {
  description = "Grafana service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].grafana_service, null)
}

output "prometheus_service" {
  description = "Prometheus service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].prometheus_service, null)
}

output "alertmanager_service" {
  description = "Alertmanager service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].alertmanager_service, null)
}

# ─── Cost Monitoring (OpenCost) ───────────────────────────────────────────────

output "opencost_namespace" {
  description = "OpenCost namespace (null when not installed)"
  value       = try(module.opencost[0].namespace, null)
}

output "opencost_version" {
  description = "OpenCost chart version (null when not installed)"
  value       = try(module.opencost[0].version, null)
}

output "opencost_service" {
  description = "OpenCost service name for port-forwarding (null when not installed)"
  value       = try(module.opencost[0].service_name, null)
}

output "opencost_validation_commands" {
  description = "Commands to access and validate OpenCost (null when not installed)"
  value       = try(module.opencost[0].validation_commands, null)
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

output "grafana_admin_password" {
  description = "Grafana admin password"
  sensitive   = true
  value       = var.grafana_admin_password
}
