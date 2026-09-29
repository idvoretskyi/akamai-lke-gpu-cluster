output "namespace" {
  description = "Namespace where OpenCost is deployed"
  value       = kubernetes_namespace_v1.opencost.metadata[0].name
}

output "service_name" {
  description = "OpenCost service name (for kubectl port-forward)"
  value       = helm_release.opencost.name
}
