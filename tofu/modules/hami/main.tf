# Create namespace for HAMi.
resource "kubernetes_namespace_v1" "hami" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "hami"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install HAMi (Heterogeneous AI Computing Virtualization middleware) via Helm.
# HAMi replaces the NVIDIA device plugin with a vGPU-aware one, so a single
# physical GPU can be split into multiple schedulable slices (by count and/or
# memory), and adds a scheduler extender + webhook that enforce the split.
resource "helm_release" "hami" {
  name       = "hami"
  repository = "https://project-hami.github.io/HAMi"
  chart      = "hami"
  version    = var.hami_version
  namespace  = kubernetes_namespace_v1.hami.metadata[0].name

  create_namespace = false
  depends_on       = [kubernetes_namespace_v1.hami]

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      device_split_count     = var.device_split_count
      device_memory_scaling  = var.device_memory_scaling
      device_core_scaling    = var.device_core_scaling
      scheduler_policy       = var.scheduler_policy
      node_selector          = var.node_selector
      gpu_node_toleration    = var.gpu_node_toleration
      nvidia_node_selector   = var.nvidia_node_selector
      runtime_class_name     = var.runtime_class_name
      nvidia_driver_root     = var.nvidia_driver_root
      wait_for_toolkit_ready = var.wait_for_toolkit_ready
      scheduler_leader_elect = var.scheduler_leader_elect
    })
  ]
}
