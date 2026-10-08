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

output "metrics_server_status" {
  description = "Metrics Server Helm release status (null when not installed)"
  value       = try(module.metrics_server[0].status, null)
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

output "monitoring_status" {
  description = "kube-prometheus-stack Helm release status (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].status, null)
}

output "monitoring_validation_commands" {
  description = "Commands to access and validate the monitoring stack (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].validation_commands, null)
}

output "grafana_service" {
  description = "Grafana service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].grafana_service, null)
}

output "prometheus_service" {
  description = "Prometheus service name for port-forwarding (null when not installed)"
  value       = try(module.kube_prometheus_stack[0].prometheus_service, null)
}

# ─── cert-manager / Envoy Gateway ─────────────────────────────────────────────

output "cert_manager_status" {
  description = "cert-manager Helm release status (null when not installed)"
  value       = try(module.cert_manager[0].status, null)
}

output "envoy_gateway_status" {
  description = "Envoy Gateway Helm release status (null when not installed)"
  value       = try(module.envoy_gateway[0].status, null)
}

output "envoy_gateway_validation_commands" {
  description = "Commands to validate Envoy Gateway (null when not installed)"
  value       = try(module.envoy_gateway[0].validation_commands, null)
}

# ─── KServe ───────────────────────────────────────────────────────────────────

output "kserve_namespace" {
  description = "KServe control-plane namespace (null when not installed)"
  value       = try(module.kserve[0].namespace, null)
}

output "kserve_version" {
  description = "KServe chart version (null when not installed)"
  value       = try(module.kserve[0].version, null)
}

output "kserve_status" {
  description = "KServe controller Helm release status (null when not installed)"
  value       = try(module.kserve[0].status, null)
}

output "kserve_validation_commands" {
  description = "Commands to validate KServe (null when not installed)"
  value       = try(module.kserve[0].validation_commands, null)
}

output "inference_commands" {
  description = "Commands to reach the GitOps-managed vLLM InferenceService through the Gateway (null when KServe is not installed)"
  value       = var.install_kserve ? local.inference_commands : null
}

locals {
  inference_host = "qwen3-${var.model_namespace}.${var.kserve_ingress_domain}"

  inference_commands = <<-EOT
    # Wait for READY=True (the first start downloads ~9 GB of weights)
    kubectl get inferenceservice -n ${var.model_namespace} -w

    # Forward the private Gateway to localhost:8080 (keep this running)
    kubectl port-forward -n envoy-gateway-system \
      "$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway -o name)" 8080:80

    # OpenAI-compatible chat completion; the Host header selects the InferenceService
    curl -s http://localhost:8080/openai/v1/chat/completions \
      -H 'Host: ${local.inference_host}' -H 'Content-Type: application/json' \
      -d '{"model":"qwen3","messages":[{"role":"user","content":"Hello"}]}'

    # Same thing via the example: make -C examples/kserve-chat port-forward, then chat
  EOT
}

# ─── Argo CD ──────────────────────────────────────────────────────────────────

output "argo_cd_namespace" {
  description = "Argo CD namespace (null when not installed)"
  value       = try(module.argo_cd[0].namespace, null)
}

output "argo_cd_version" {
  description = "Argo CD chart version (null when not installed)"
  value       = try(module.argo_cd[0].version, null)
}

output "argo_cd_status" {
  description = "Argo CD Helm release status (null when not installed)"
  value       = try(module.argo_cd[0].status, null)
}

output "argo_cd_applications" {
  description = "Bootstrap Argo CD Applications (null when not installed)"
  value       = try(module.argo_cd[0].application_names, null)
}

output "argo_cd_validation_commands" {
  description = "Commands to reach and validate Argo CD (null when not installed)"
  value       = try(module.argo_cd[0].validation_commands, null)
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

output "grafana_admin_password" {
  description = "Grafana admin password"
  sensitive   = true
  value       = var.grafana_admin_password
}
