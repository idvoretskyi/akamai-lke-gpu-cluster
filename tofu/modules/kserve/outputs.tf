output "namespace" {
  description = "Namespace of the KServe control plane"
  value       = helm_release.kserve.namespace
}

output "release_name" {
  description = "Helm release name of the KServe controller"
  value       = helm_release.kserve.name
}

output "version" {
  description = "KServe chart version"
  value       = helm_release.kserve.version
}

output "status" {
  description = "Status of the KServe controller Helm release"
  value       = helm_release.kserve.status
}

output "gateway_name" {
  description = "Name of the shared Gateway InferenceServices attach to"
  value       = "kserve-ingress-gateway"
}

output "ingress_domain" {
  description = "Domain used in InferenceService hostnames"
  value       = var.ingress_domain
}

output "validation_commands" {
  description = "Commands to validate KServe"
  value       = <<-EOT
    # Controller pod, CRDs and serving runtimes
    kubectl get pods -n ${helm_release.kserve.namespace}
    kubectl get crd | grep serving.kserve.io
    kubectl get clusterservingruntimes

    # The shared Gateway should be Programmed
    kubectl get gateway -n ${helm_release.kserve.namespace} kserve-ingress-gateway

    # InferenceServices in every namespace
    kubectl get inferenceservices -A
  EOT
}
