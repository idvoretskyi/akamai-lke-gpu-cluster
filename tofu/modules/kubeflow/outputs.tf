output "namespace" {
  description = "Primary Kubeflow namespace"
  value       = "kubeflow"
}

output "version" {
  description = "Installed Kubeflow manifests version"
  value       = var.manifests_version
}

output "dashboard_port_forward" {
  description = "Command to reach the Kubeflow Central Dashboard locally"
  value       = "kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
}

output "default_credentials" {
  description = "Default Dex static user for the Central Dashboard. Change immediately for any non-throwaway cluster."
  value       = "user@example.com / 12341234"
}

output "validation_commands" {
  description = "Commands to validate the Kubeflow installation"
  value = [
    "kubectl get pods -n kubeflow",
    "kubectl get pods -n istio-system",
    "kubectl -n kubeflow rollout status deploy/ml-pipeline",
  ]
}
