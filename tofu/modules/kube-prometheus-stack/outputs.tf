output "namespace" {
  description = "Namespace where monitoring stack is deployed"
  value       = kubernetes_namespace.monitoring.metadata[0].name
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

output "alertmanager_service" {
  description = "Alertmanager service name for port-forwarding"
  value       = "${helm_release.kube_prometheus_stack.name}-alertmanager"
}

output "validation_commands" {
  description = "Commands to validate monitoring stack functionality"
  value       = <<-EOT
    # Check all monitoring pods
    kubectl get pods -n ${kubernetes_namespace.monitoring.metadata[0].name}

    # Access Grafana (port 3000)
    kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/${helm_release.kube_prometheus_stack.name}-grafana 3000:80
    # Then visit: http://localhost:3000

    # Access Prometheus (port 9090)
    kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/${helm_release.kube_prometheus_stack.name}-prometheus 9090:9090
    # Then visit: http://localhost:9090/targets

    # Access Alertmanager (port 9093)
    kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/${helm_release.kube_prometheus_stack.name}-alertmanager 9093:9093
    # Then visit: http://localhost:9093
  EOT
}
