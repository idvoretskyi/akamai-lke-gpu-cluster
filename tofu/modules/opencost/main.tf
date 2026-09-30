# Create namespace for OpenCost.
resource "kubernetes_namespace_v1" "opencost" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "opencost"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install OpenCost via Helm.
resource "helm_release" "opencost" {
  name       = "opencost"
  repository = "https://opencost.github.io/opencost-helm-chart"
  chart      = "opencost"
  version    = var.opencost_chart_version
  namespace  = kubernetes_namespace_v1.opencost.metadata[0].name

  create_namespace = false

  # No wait_for_jobs: the opencost chart ships no post-install Jobs.
  timeout = 300
  wait    = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      prometheus_url         = var.prometheus_url
      enable_ui              = var.enable_ui
      enable_service_monitor = var.enable_service_monitor
      resources              = var.resources
      extra_labels           = var.extra_labels
      node_selector          = var.node_selector
    })
  ]
}
