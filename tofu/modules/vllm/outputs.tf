output "namespace" {
  description = "vLLM namespace"
  value       = kubernetes_namespace_v1.vllm.metadata[0].name
}

output "release_name" {
  description = "vLLM Helm release name"
  value       = helm_release.vllm.name
}

output "version" {
  description = "vllm-stack chart version"
  value       = helm_release.vllm.version
}

output "status" {
  description = "vLLM Helm release status"
  value       = helm_release.vllm.status
}

output "service_name" {
  description = "Engine Service name (ClusterIP)"
  value       = local.service_name
}

output "service_port" {
  description = "Engine Service port"
  value       = local.service_port
}

output "base_url" {
  description = "In-cluster OpenAI-compatible base URL"
  value       = "http://${local.service_name}.${kubernetes_namespace_v1.vllm.metadata[0].name}.svc.cluster.local:${local.service_port}/v1"
}

output "served_model_name" {
  description = "Model id to use in API requests"
  value       = var.served_model_name
}

output "api_key" {
  description = "API key for the vLLM endpoint (generated when none was given)"
  value       = local.api_key
  sensitive   = true
}

output "port_forward_command" {
  description = "Forward the vLLM API to localhost:8000"
  value       = "kubectl port-forward -n ${kubernetes_namespace_v1.vllm.metadata[0].name} service/${local.service_name} 8000:${local.service_port}"
}
