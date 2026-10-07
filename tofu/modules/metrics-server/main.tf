# Metrics Server — provides the resource metrics API for kubectl top and HPA.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_version
  namespace  = var.namespace

  # kube-system already exists; the module never creates its namespace.
  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      replicas      = var.replicas
      resources     = var.resources
      node_selector = var.node_selector
    })
  ]
}
