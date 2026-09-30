output "namespace" {
  description = "Namespace where Ollama is deployed"
  value       = kubernetes_namespace_v1.ollama.metadata[0].name
}

output "release_name" {
  description = "Helm release name for Ollama"
  value       = helm_release.ollama.name
}

output "version" {
  description = "Ollama chart version"
  value       = helm_release.ollama.version
}

output "status" {
  description = "Status of the Ollama Helm release"
  value       = helm_release.ollama.status
}

output "service_name" {
  description = "Ollama service name (for kubectl port-forward)"
  value       = helm_release.ollama.name
}

output "models" {
  description = "Models pulled on startup"
  value       = var.models
}

output "validation_commands" {
  description = "Commands to reach and validate Ollama"
  value       = <<-EOT
    # Forward the Ollama API to localhost:11434 (keep this running)
    kubectl port-forward --namespace ${kubernetes_namespace_v1.ollama.metadata[0].name} service/${helm_release.ollama.name} 11434:11434

    # List downloaded models
    curl http://localhost:11434/api/tags

    # Chat with a model (native API)
    curl http://localhost:11434/api/chat -d '{"model":"${try(var.models[0], "MODEL")}","messages":[{"role":"user","content":"Hello"}],"stream":false}'

    # OpenAI-compatible endpoint: base URL http://localhost:11434/v1 (any API key)

    # Show which model is loaded and whether it is fully on the GPU
    kubectl exec -n ${kubernetes_namespace_v1.ollama.metadata[0].name} deploy/${helm_release.ollama.name} -- ollama ps

    # Watch GPU memory use
    kubectl exec -n ${kubernetes_namespace_v1.ollama.metadata[0].name} deploy/${helm_release.ollama.name} -- nvidia-smi
  EOT
}
