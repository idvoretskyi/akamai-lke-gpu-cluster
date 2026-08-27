output "namespace" {
  description = "Namespace where HAMi is installed"
  value       = kubernetes_namespace_v1.hami.metadata[0].name
}

output "release_name" {
  description = "Helm release name for HAMi"
  value       = helm_release.hami.name
}

output "version" {
  description = "HAMi chart version"
  value       = helm_release.hami.version
}

output "status" {
  description = "Status of the HAMi Helm release"
  value       = helm_release.hami.status
}

output "validation_commands" {
  description = "Commands to validate GPU virtualization via HAMi"
  value       = <<-EOT
    # Check HAMi pods (scheduler, device-plugin, webhook)
    kubectl get pods -n ${kubernetes_namespace_v1.hami.metadata[0].name}

    # Verify vGPU-sliced capacity is advertised (nvidia.com/gpu count now
    # reflects device_split_count slices per physical GPU, not physical count)
    kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'

    # Two pods sharing one physical GPU, each requesting an explicit memory
    # slice (see examples/hami-validation for the tested manifest —
    # `kubectl run --limits=...` was removed in kubectl 1.24+)
    kubectl apply -f examples/hami-validation/nvidia-smi-shared-pods.yaml
    kubectl wait pod/hami-validation-a pod/hami-validation-b --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
    kubectl logs hami-validation-a && kubectl logs hami-validation-b

    # A Pod that only requests nvidia.com/gpu (no gpumem) gets the module's
    # default_gpu_memory slice instead of the whole physical GPU (see
    # examples/gpu-validation for the tested manifest)
    kubectl apply -f examples/gpu-validation/nvidia-smi-pod.yaml
    kubectl wait pod/gpu-validation --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s
    kubectl logs pod/gpu-validation

    # Check HAMi scheduler logs
    kubectl logs -n ${kubernetes_namespace_v1.hami.metadata[0].name} -l app.kubernetes.io/component=hami-scheduler
  EOT
}
