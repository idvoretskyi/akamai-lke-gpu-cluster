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
  depends_on       = [kubernetes_namespace_v1.opencost]

  timeout = 300
  wait    = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      prometheus_url         = var.prometheus_url
      enable_ui              = var.enable_ui
      enable_service_monitor = var.enable_service_monitor
      requests_cpu           = var.resources.requests.cpu
      requests_memory        = var.resources.requests.memory
      limits_cpu             = var.resources.limits.cpu
      limits_memory          = var.resources.limits.memory
      extra_labels           = var.extra_labels
      node_selector          = var.node_selector
    })
  ]
}
