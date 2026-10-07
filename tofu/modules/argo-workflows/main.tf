# Create namespace for Argo Workflows. Workflows run in this namespace too
# (singleNamespace), which keeps RBAC to a Role/RoleBinding pair.
resource "kubernetes_namespace_v1" "argo" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "argo-workflows"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install Argo Workflows via Helm.
resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.argo.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      auth_mode              = var.auth_mode
      enable_service_monitor = var.enable_service_monitor
      resources              = var.resources
      node_selector          = var.node_selector
    })
  ]
}
