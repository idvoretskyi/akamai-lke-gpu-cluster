output "namespace" {
  description = "Namespace where Open WebUI is deployed"
  value       = kubernetes_namespace_v1.open_webui.metadata[0].name
}

output "release_name" {
  description = "Helm release name for Open WebUI"
  value       = helm_release.open_webui.name
}

output "version" {
  description = "Open WebUI chart version"
  value       = helm_release.open_webui.version
}

output "status" {
  description = "Status of the Open WebUI Helm release"
  value       = helm_release.open_webui.status
}

output "service_name" {
  description = "Open WebUI service name (for kubectl port-forward)"
  value       = helm_release.open_webui.name
}

output "validation_commands" {
  description = "Commands to access and validate Open WebUI"
  value       = <<-EOT
    # Port-forward the UI
    kubectl port-forward --namespace ${kubernetes_namespace_v1.open_webui.metadata[0].name} service/${helm_release.open_webui.name} 8080:80
    # http://localhost:8080 (the first account you create is the admin)

    # Verify the pod is running
    kubectl get pods -n ${kubernetes_namespace_v1.open_webui.metadata[0].name}
  EOT
}
