output "namespace" {
  description = "Namespace where OpenCost is deployed"
  value       = kubernetes_namespace_v1.opencost.metadata[0].name
}

output "release_name" {
  description = "Helm release name for OpenCost"
  value       = helm_release.opencost.name
}

output "version" {
  description = "OpenCost chart version"
  value       = helm_release.opencost.version
}

output "status" {
  description = "Status of the OpenCost Helm release"
  value       = helm_release.opencost.status
}

output "service_name" {
  description = "OpenCost service name (for kubectl port-forward)"
  value       = helm_release.opencost.name
}

output "validation_commands" {
  description = "Commands to access and validate OpenCost"
  value       = <<-EOT
    # Port-forward OpenCost UI and API
    kubectl port-forward --namespace ${kubernetes_namespace_v1.opencost.metadata[0].name} service/${helm_release.opencost.name} 9090:9090

    # Access OpenCost UI
    # http://localhost:9090

    # Check cost allocation (last 60 minutes)
    # http://localhost:9003/allocation/compute?window=60m

    # Verify OpenCost pods are running
    kubectl get pods -n ${kubernetes_namespace_v1.opencost.metadata[0].name}

    # Check OpenCost logs
    kubectl logs -n ${kubernetes_namespace_v1.opencost.metadata[0].name} -l app.kubernetes.io/name=opencost
  EOT
}
