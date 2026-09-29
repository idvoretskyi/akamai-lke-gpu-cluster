output "namespace" {
  description = "Namespace where metrics-server is deployed"
  value       = helm_release.metrics_server.namespace
}
