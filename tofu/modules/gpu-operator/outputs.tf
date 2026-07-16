output "namespace" {
  description = "Namespace where GPU operator is installed"
  value       = kubernetes_namespace_v1.gpu_operator.metadata[0].name
}

output "release_name" {
  description = "Helm release name for GPU operator"
  value       = helm_release.gpu_operator.name
}

output "version" {
  description = "GPU Operator chart version"
  value       = helm_release.gpu_operator.version
}

output "status" {
  description = "Status of the GPU operator Helm release"
  value       = helm_release.gpu_operator.status
}

output "validation_commands" {
  description = "Commands to validate GPU availability"
  value       = <<-EOT
    # Check GPU operator pods
    kubectl get pods -n ${kubernetes_namespace_v1.gpu_operator.metadata[0].name}

    # Verify GPU devices are detected
    kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'

    # Run GPU test workload (see examples/gpu-validation for the tested
    # manifest — `kubectl run --limits=...` was removed in kubectl 1.24+)
    kubectl apply -f examples/gpu-validation/nvidia-smi-pod.yaml
    kubectl wait pod/gpu-validation --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
    kubectl logs pod/gpu-validation

    # Check DCGM metrics (if enabled)
    kubectl get pods -n ${kubernetes_namespace_v1.gpu_operator.metadata[0].name} -l app=nvidia-dcgm-exporter
  EOT
}
