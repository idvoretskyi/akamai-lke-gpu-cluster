# Create namespace for Argo CD.
resource "kubernetes_namespace_v1" "argo_cd" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "argo-cd"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Argo CD — GitOps controller. Single replicas, no Dex/notifications: a lab
# install reached with kubectl port-forward and the initial admin password.
resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.argo_cd.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      node_selector          = var.node_selector
      enable_service_monitor = var.enable_service_monitor
    })
  ]
}

# Bootstrap Applications (app-of-apps entry points). Application is a custom
# resource whose CRD only exists after the release above, so it is installed
# through a tiny local chart rather than kubernetes_manifest. Each Application
# carries Argo CD's resources finalizer: destroying this release deletes the
# workloads it synced (e.g. the InferenceService) before Argo CD goes away.
resource "helm_release" "applications" {
  count = length(var.applications) > 0 ? 1 : 0

  name      = "argo-cd-applications"
  chart     = "${path.module}/chart"
  namespace = kubernetes_namespace_v1.argo_cd.metadata[0].name

  create_namespace = false

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = 300

  values = [
    yamlencode({ applications = var.applications })
  ]

  depends_on = [helm_release.argo_cd]
}
