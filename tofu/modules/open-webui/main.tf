# Create namespace for Open WebUI.
resource "kubernetes_namespace_v1" "open_webui" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "open-webui"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install Open WebUI via Helm. The chart's bundled Ollama, Pipelines and Redis
# are disabled: the UI talks to the Ollama release this repo already installs.
resource "helm_release" "open_webui" {
  name       = "open-webui"
  repository = "https://helm.openwebui.com"
  chart      = "open-webui"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.open_webui.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      ollama_url    = var.ollama_url
      storage_size  = var.storage_size
      storage_class = var.storage_class
      resources     = var.resources
      node_selector = var.node_selector
      enable_signup = var.enable_signup
    })
  ]
}
