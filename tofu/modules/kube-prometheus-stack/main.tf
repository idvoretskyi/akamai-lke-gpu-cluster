# Create monitoring namespace.
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "kube-prometheus-stack"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# kube-prometheus-stack — Prometheus, Grafana, Alertmanager, Node Exporter, KSM.
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  create_namespace = false
  depends_on       = [kubernetes_namespace_v1.monitoring]

  wait          = true
  timeout       = 900
  wait_for_jobs = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      prometheus_retention      = var.prometheus_retention
      prometheus_storage_size   = var.prometheus_storage_size
      alertmanager_storage_size = var.alertmanager_storage_size
      grafana_admin_password    = var.grafana_admin_password
      grafana_storage_size      = var.grafana_storage_size
      storage_class             = var.storage_class
      enable_gpu_monitoring     = var.enable_gpu_monitoring
      prometheus_resources      = var.prometheus_resources
      grafana_resources         = var.grafana_resources
      alertmanager_resources    = var.alertmanager_resources
    })
  ]
}
