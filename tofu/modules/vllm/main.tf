# Create namespace for vLLM.
resource "kubernetes_namespace_v1" "vllm" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "vllm"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install vLLM via the vllm-project production-stack chart (vllm-stack), with
# the router, cache server and LoRA controller disabled: a single engine
# Deployment serving one model behind a ClusterIP Service.
#
# vLLM downloads the model weights from Hugging Face on first start, into the
# PVC (HF_HOME=/data), so the first install takes as long as the download.
# Like the Ollama module, the release is deliberately not atomic: a rollback
# of a timed-out first install would delete the PVC with the partial download.
# upgrade_install lets the next apply adopt a release that exists in the
# cluster but not in state, instead of failing on "name already in use".
resource "helm_release" "vllm" {
  name       = "vllm"
  repository = "https://vllm-project.github.io/production-stack"
  chart      = "vllm-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.vllm.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = false
  upgrade_install = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      model_name             = var.model_name
      model                  = var.model
      model_revision         = var.model_revision
      image_repository       = var.image_repository
      image_tag              = var.image_tag
      max_model_len          = var.max_model_len
      gpu_memory_utilization = var.gpu_memory_utilization
      dtype                  = var.dtype
      extra_args             = var.extra_args
      gpu_memory_mib         = var.gpu_memory_mib
      gpu_node_toleration    = var.gpu_node_toleration
      node_selector          = var.node_selector
      resources              = var.resources
      shm_size               = var.shm_size
      storage_size           = var.storage_size
      storage_class          = var.storage_class
      enable_service_monitor = var.enable_service_monitor
      startup_probe_failures = ceil(var.timeout / 10)
      hf_token_secret        = var.hf_token == null ? null : kubernetes_secret_v1.hf_token[0].metadata[0].name
    })
  ]
}

# Hugging Face token for gated models. Kept in its own Secret rather than in
# the Helm values, so it never appears in the rendered values or plan output;
# the chart references it by name and injects it as HF_TOKEN. (Passing it via
# set_sensitive on servingEngineSpec.modelSpec[0] would replace the whole
# modelSpec list, since Helm doesn't merge lists.)
resource "kubernetes_secret_v1" "hf_token" {
  count = var.hf_token == null ? 0 : 1

  metadata {
    name      = "vllm-hf-token"
    namespace = kubernetes_namespace_v1.vllm.metadata[0].name
  }

  data = {
    token = var.hf_token
  }
}
