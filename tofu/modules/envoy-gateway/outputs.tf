output "namespace" {
  description = "Namespace where Envoy Gateway and its proxies run"
  value       = helm_release.envoy_gateway.namespace
}

output "release_name" {
  description = "Helm release name for Envoy Gateway"
  value       = helm_release.envoy_gateway.name
}

output "version" {
  description = "Envoy Gateway chart version"
  value       = helm_release.envoy_gateway.version
}

output "status" {
  description = "Status of the Envoy Gateway Helm release"
  value       = helm_release.envoy_gateway.status
}

output "gateway_class_name" {
  description = "Name of the GatewayClass backed by Envoy Gateway"
  value       = var.gateway_class_name
}

output "validation_commands" {
  description = "Commands to validate Envoy Gateway"
  value       = <<-EOT
    # Controller and Envoy proxy pods
    kubectl get pods -n ${helm_release.envoy_gateway.namespace}

    # GatewayClass should be Accepted, Gateways Programmed
    kubectl get gatewayclass ${var.gateway_class_name}
    kubectl get gateways -A
  EOT
}
