output "namespace" {
  description = "Namespace where Argo Workflows is deployed (and where workflows run)"
  value       = kubernetes_namespace_v1.argo.metadata[0].name
}

output "release_name" {
  description = "Helm release name for Argo Workflows"
  value       = helm_release.argo_workflows.name
}

output "version" {
  description = "Argo Workflows chart version"
  value       = helm_release.argo_workflows.version
}

output "status" {
  description = "Status of the Argo Workflows Helm release"
  value       = helm_release.argo_workflows.status
}

output "service_account" {
  description = "Service account workflows run as (set serviceAccountName in the Workflow spec)"
  value       = "argo-workflow"
}

output "validation_commands" {
  description = "Commands to access and validate Argo Workflows"
  value       = <<-EOT
    # Port-forward the Argo UI (plain HTTP)
    kubectl port-forward --namespace ${kubernetes_namespace_v1.argo.metadata[0].name} service/${helm_release.argo_workflows.name}-server 2746:2746
    # http://localhost:2746

    # Verify pods are running
    kubectl get pods -n ${kubernetes_namespace_v1.argo.metadata[0].name}

    # Run a GPU workflow on a HAMi slice
    make -C examples/argo-gpu-job submit wait logs
  EOT
}
