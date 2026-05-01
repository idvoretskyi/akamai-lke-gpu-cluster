# Create namespace for GPU Operator.
resource "kubernetes_namespace_v1" "gpu_operator" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "gpu-operator"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install NVIDIA GPU Operator via Helm.
resource "helm_release" "gpu_operator" {
  name       = "gpu-operator"
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_version
  namespace  = kubernetes_namespace_v1.gpu_operator.metadata[0].name

  create_namespace = false
  depends_on       = [kubernetes_namespace_v1.gpu_operator]

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      install_driver              = var.install_driver
      enable_dcgm_exporter        = var.enable_dcgm_exporter
      enable_node_status_exporter = var.enable_node_status_exporter
    })
  ]
}
