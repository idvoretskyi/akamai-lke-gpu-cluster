output "namespace" {
  description = "Namespace where monitoring stack is deployed"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "grafana_service" {
  description = "Grafana service name for port-forwarding"
  value       = "${helm_release.kube_prometheus_stack.name}-grafana"
}

output "prometheus_service" {
  description = "Prometheus service name for port-forwarding"
  value       = "${helm_release.kube_prometheus_stack.name}-prometheus"
}

output "prometheus_internal_url" {
  description = "In-cluster URL for Prometheus, suitable for consumption by other workloads (e.g. OpenCost)"
  value       = "http://${helm_release.kube_prometheus_stack.name}-prometheus.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local:9090"
}
