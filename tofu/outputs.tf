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

output "kubeconfig_path" {
  description = "Path to the merged kubeconfig file (when merge_kubeconfig = true)"
  value       = var.merge_kubeconfig ? "~/.kube/config (merged)" : "kubeconfig merge disabled — manage kubeconfig externally"
}

output "cluster_dashboard_url" {
  description = "URL to the Linode cluster dashboard"
  value       = linode_lke_cluster.gpu_cluster.dashboard_url
}

output "gpu_node_pool_id" {
  description = "The ID of the GPU node pool"
  value       = linode_lke_cluster.gpu_cluster.pool[0].id
}

output "gpu_node_pool_count" {
  description = "Number of nodes in the GPU pool"
  value       = linode_lke_cluster.gpu_cluster.pool[0].count
}

output "firewall_id" {
  description = "The ID of the firewall protecting the cluster"
  value       = linode_firewall.lke_firewall.id
}

output "kubectl_context" {
  description = "The kubectl context name for this cluster"
  value       = "lke${linode_lke_cluster.gpu_cluster.id}-ctx"
}

output "gpu_operator_namespace" {
  description = "GPU Operator namespace (null when not installed)"
  value       = var.install_gpu_operator ? module.gpu_operator[0].namespace : null
}

output "gpu_operator_status" {
  description = "GPU Operator Helm release status (null when not installed)"
  value       = var.install_gpu_operator ? module.gpu_operator[0].status : null
}

output "metrics_server_namespace" {
  description = "Metrics Server namespace (null when not installed)"
  value       = var.install_metrics_server ? module.metrics_server[0].namespace : null
}

output "monitoring_namespace" {
  description = "Monitoring stack namespace (null when not installed)"
  value       = var.install_monitoring ? module.kube_prometheus_stack[0].namespace : null
}

output "grafana_service" {
  description = "Grafana service name for port-forwarding (null when not installed)"
  value       = var.install_monitoring ? module.kube_prometheus_stack[0].grafana_service : null
}

output "prometheus_service" {
  description = "Prometheus service name for port-forwarding (null when not installed)"
  value       = var.install_monitoring ? module.kube_prometheus_stack[0].prometheus_service : null
}

output "gpu_validation_commands" {
  description = "Commands to validate GPU setup (when GPU Operator is installed)"
  value       = var.install_gpu_operator ? module.gpu_operator[0].validation_commands : "GPU Operator not installed"
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  sensitive   = true
  value       = var.grafana_admin_password
}
