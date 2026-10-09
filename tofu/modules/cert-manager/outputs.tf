output "namespace" {
  description = "Namespace where cert-manager is deployed"
  value       = helm_release.cert_manager.namespace
}

output "release_name" {
  description = "Helm release name for cert-manager"
  value       = helm_release.cert_manager.name
}

output "version" {
  description = "cert-manager chart version"
  value       = helm_release.cert_manager.version
}

output "status" {
  description = "Status of the cert-manager Helm release"
  value       = helm_release.cert_manager.status
}

output "validation_commands" {
  description = "Commands to validate cert-manager"
  value       = <<-EOT
    # cert-manager pods (controller, webhook, cainjector)
    kubectl get pods -n ${helm_release.cert_manager.namespace}

    # Certificates across the cluster (KServe's webhook cert should be Ready)
    kubectl get certificates -A
  EOT
}
