# Create namespace for cert-manager.
resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "cert-manager"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# cert-manager — issues the TLS certificates for KServe's admission webhooks
# (KServe's chart ships a self-signed Issuer and the Certificate; cert-manager
# signs it and injects the CA bundle into the webhook configurations).
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name

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
