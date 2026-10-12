output "namespace" {
  description = "Namespace where Argo CD is deployed"
  value       = helm_release.argo_cd.namespace
}

output "release_name" {
  description = "Helm release name for Argo CD"
  value       = helm_release.argo_cd.name
}

output "version" {
  description = "Argo CD chart version"
  value       = helm_release.argo_cd.version
}

output "status" {
  description = "Status of the Argo CD Helm release"
  value       = helm_release.argo_cd.status
}

output "application_names" {
  description = "Names of the bootstrap Applications"
  value       = [for a in var.applications : a.name]
}

output "validation_commands" {
  description = "Commands to validate Argo CD"
  value       = <<-EOT
    # Argo CD pods
    kubectl get pods -n ${helm_release.argo_cd.namespace}

    # Applications: SYNC STATUS should be Synced, HEALTH Healthy
    kubectl get applications -n ${helm_release.argo_cd.namespace}

    # UI on http://localhost:8081 (user: admin); 8080 is the model Gateway
    kubectl -n ${helm_release.argo_cd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
    kubectl port-forward -n ${helm_release.argo_cd.namespace} svc/argo-cd-argocd-server 8081:80
  EOT
}
