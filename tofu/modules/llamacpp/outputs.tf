output "namespace" {
  description = "llama.cpp namespace"
  value       = kubernetes_namespace_v1.llamacpp.metadata[0].name
}

output "release_name" {
  description = "llama.cpp Helm release name"
  value       = helm_release.llamacpp.name
}

output "version" {
  description = "app-template chart version"
  value       = helm_release.llamacpp.version
}

output "status" {
  description = "llama.cpp Helm release status"
  value       = helm_release.llamacpp.status
}

output "service_name" {
  description = "Service name (ClusterIP)"
  value       = local.service_name
}

output "service_port" {
  description = "Service port"
  value       = local.service_port
}

output "base_url" {
  description = "In-cluster OpenAI-compatible base URL (reachable only from allowed_ingress_namespaces)"
  value       = "http://${local.service_name}.${kubernetes_namespace_v1.llamacpp.metadata[0].name}.svc.cluster.local:${local.service_port}/v1"
}

output "served_model_name" {
  description = "Model id to use in API requests"
  value       = var.served_model_name
}

output "api_key" {
  description = "API key for the llama.cpp endpoint (generated when none was given)"
  value       = local.api_key
  sensitive   = true
}

output "port_forward_command" {
  description = "Forward the llama.cpp API to localhost:8000"
  value       = "kubectl port-forward -n ${kubernetes_namespace_v1.llamacpp.metadata[0].name} service/${local.service_name} 8000:${local.service_port}"
}
