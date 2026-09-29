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

# ─── Modules ──────────────────────────────────────────────────────────────────
# Namespace and service-name outputs for kubectl/port-forward convenience.
# null when the corresponding install_* variable is false.

output "gpu_operator_namespace" {
  description = "GPU Operator namespace (null when not installed)"
  value       = try(module.gpu_operator[0].namespace, null)
}

output "hami_namespace" {
  description = "HAMi namespace (null when not installed)"
  value       = try(module.hami[0].namespace, null)
}

output "metrics_server_namespace" {
  description = "Metrics Server namespace (null when not installed)"
  value       = try(module.metrics_server[0].namespace, null)
}

output "monitoring_namespace" {
  description = "Monitoring stack namespace (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].namespace, null)
}

output "grafana_service" {
  description = "Grafana service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].grafana_service, null)
}

output "prometheus_service" {
  description = "Prometheus service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].prometheus_service, null)
}

output "opencost_namespace" {
  description = "OpenCost namespace (null when not installed)"
  value       = try(module.opencost[0].namespace, null)
}

output "opencost_service" {
  description = "OpenCost service name for port-forwarding (null when not installed)"
  value       = try(module.opencost[0].service_name, null)
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

output "grafana_admin_password" {
  description = "Grafana admin password"
  sensitive   = true
  value       = var.grafana_admin_password
}
