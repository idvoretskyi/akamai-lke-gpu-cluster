# Create namespace for Ollama.
resource "kubernetes_namespace_v1" "ollama" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "ollama"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install Ollama via the otwld/ollama-helm chart.
#
# The chart pulls var.models in a postStart hook, so the pod only turns Ready
# once every model is on the PVC. The first install therefore takes as long
# as the downloads (tens of GB), which is why var.timeout defaults much higher
# than in the other modules. Later restarts are fast, since the models are
# already on the persistent volume.
#
# atomic is deliberately false here, unlike the other modules: an atomic
# rollback of a timed-out first install would uninstall the release, delete
# the PVC with its partial downloads (and, with the Retain storage class,
# orphan the volume). Without it, re-running `tofu apply` resumes the pulls.
resource "helm_release" "ollama" {
  name       = "ollama"
  repository = "https://otwld.github.io/ollama-helm/"
  chart      = "ollama"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.ollama.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = false
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      image_tag           = var.image_tag
      models              = var.models
      gpu_memory_mib      = var.gpu_memory_mib
      gpu_node_toleration = var.gpu_node_toleration
      node_selector       = var.node_selector
      resources           = var.resources
      storage_size        = var.storage_size
      storage_class       = var.storage_class
      env = merge(
        {
          OLLAMA_KEEP_ALIVE      = var.keep_alive
          OLLAMA_CONTEXT_LENGTH  = tostring(var.context_length)
          OLLAMA_FLASH_ATTENTION = var.flash_attention ? "1" : "0"
          OLLAMA_KV_CACHE_TYPE   = var.kv_cache_type
          # One model resident at a time: the GPU fits one of the default
          # models, not two.
          OLLAMA_MAX_LOADED_MODELS = "1"
        },
        var.extra_env,
      )
    })
  ]
}
