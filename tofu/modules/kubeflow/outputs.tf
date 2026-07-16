output "kubeflow_ref" {
  description = "Git ref of kubeflow/community-distribution installed"
  value       = var.kubeflow_ref
}

output "validation_commands" {
  description = "Commands to access and validate the Kubeflow install"
  value       = <<-EOT
    # Check core Kubeflow namespaces
    kubectl get pods -n cert-manager
    kubectl get pods -n istio-system
    kubectl get pods -n auth
    kubectl get pods -n oauth2-proxy
    kubectl get pods -n knative-serving
    kubectl get pods -n kubeflow
    kubectl get pods -n kubeflow-user-example-com

    # Port-forward the Istio ingress gateway to reach the Central Dashboard
    kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
    # Then open http://localhost:8080 — default login user@example.com / 12341234
  EOT
}
