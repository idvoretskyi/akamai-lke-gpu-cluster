# Metrics Server — provides the resource metrics API for kubectl top and HPA.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = var.namespace

  # No wait_for_jobs: the metrics-server chart ships no post-install Jobs.
  timeout = 600
  wait    = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      replicas        = var.replicas
      requests_cpu    = var.resources.requests.cpu
      requests_memory = var.resources.requests.memory
      limits_cpu      = var.resources.limits.cpu
      limits_memory   = var.resources.limits.memory
      node_selector   = var.node_selector
    })
  ]
}
