locals {
  # Service name rendered by the vllm-stack chart for the single engine.
  service_name = "${helm_release.vllm.name}-${var.model_name}-engine-service"
  deployment   = "${helm_release.vllm.name}-${var.model_name}-deployment-vllm"
}

output "namespace" {
  description = "Namespace where vLLM is deployed"
  value       = kubernetes_namespace_v1.vllm.metadata[0].name
}

output "release_name" {
  description = "Helm release name for vLLM"
  value       = helm_release.vllm.name
}

output "version" {
  description = "vllm-stack chart version"
  value       = helm_release.vllm.version
}

output "status" {
  description = "Status of the vLLM Helm release"
  value       = helm_release.vllm.status
}

output "service_name" {
  description = "vLLM engine service name (for kubectl port-forward; service port 80)"
  value       = local.service_name
}

output "deployment_name" {
  description = "vLLM engine Deployment name"
  value       = local.deployment
}

output "model" {
  description = "Hugging Face model served by vLLM"
  value       = var.model
}

output "validation_commands" {
  description = "Commands to reach and validate vLLM"
  value       = <<-EOT
    # Forward the OpenAI-compatible API to localhost:8000 (keep this running)
    kubectl port-forward --namespace ${kubernetes_namespace_v1.vllm.metadata[0].name} service/${local.service_name} 8000:80

    # List the served model
    curl http://localhost:8000/v1/models

    # Chat completion
    curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"${var.model}","messages":[{"role":"user","content":"Hello"}]}'

    # Prometheus metrics (TTFT, throughput, KV cache usage)
    curl -s http://localhost:8000/metrics | grep '^vllm:'

    # Watch GPU memory use
    kubectl exec -n ${kubernetes_namespace_v1.vllm.metadata[0].name} deploy/${local.deployment} -- nvidia-smi
  EOT
}
