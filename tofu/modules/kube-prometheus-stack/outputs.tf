output "namespace" {
  description = "Namespace where monitoring stack is deployed"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "release_name" {
  description = "Helm release name for kube-prometheus-stack"
  value       = helm_release.kube_prometheus_stack.name
}

output "version" {
  description = "Kube Prometheus Stack chart version"
  value       = helm_release.kube_prometheus_stack.version
}

output "status" {
  description = "Status of the kube-prometheus-stack Helm release"
  value       = helm_release.kube_prometheus_stack.status
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

output "validation_commands" {
  description = "Commands to validate monitoring stack functionality"
  value       = <<-EOT
    # Check all monitoring pods
    kubectl get pods -n ${kubernetes_namespace_v1.monitoring.metadata[0].name}

    # Access Grafana (port 3000)
    kubectl port-forward -n ${kubernetes_namespace_v1.monitoring.metadata[0].name} svc/${helm_release.kube_prometheus_stack.name}-grafana 3000:80
    # Then visit: http://localhost:3000

    # Access Prometheus (port 9090)
    kubectl port-forward -n ${kubernetes_namespace_v1.monitoring.metadata[0].name} svc/${helm_release.kube_prometheus_stack.name}-prometheus 9090:9090
    # Then visit: http://localhost:9090/targets
  EOT
}
