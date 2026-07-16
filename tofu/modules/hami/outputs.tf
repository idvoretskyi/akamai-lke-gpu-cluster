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

    # Run two pods sharing one physical GPU (schedulerName + gpumem request)
    kubectl run hami-test-1 --rm -it --restart=Never \
      --overrides='{"spec":{"schedulerName":"hami-scheduler"}}' \
      --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
      --limits=nvidia.com/gpu=1,nvidia.com/gpumem=2000 \
      -- nvidia-smi

    # Check HAMi scheduler logs
    kubectl logs -n ${kubernetes_namespace_v1.hami.metadata[0].name} -l app.kubernetes.io/component=hami-scheduler
  EOT
}
