# vLLM: one OpenAI-compatible model server on the GPU pool, installed with the
# vLLM production-stack chart (vllm-stack) with its router disabled. With a
# single GPU and a single user the router's replica-aware routing has nothing
# to do, so the engine Service is exposed directly (ClusterIP only).

resource "kubernetes_namespace_v1" "vllm" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "vllm"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# API key: the caller's value, or a generated one when none is given. vLLM
# only guards /v1/* with it; /health and /metrics stay open inside the
# cluster so probes and Prometheus keep working.
resource "random_password" "api_key" {
  count   = var.api_key == null ? 1 : 0
  length  = 40
  special = false
}

locals {
  api_key = var.api_key != null ? var.api_key : random_password.api_key[0].result

  # modelSpec name: fixed so the Service name stays stable across presets.
  model_name   = "coder"
  service_name = "${var.release_name}-${local.model_name}-engine-service"
  service_port = 8000

  vllm_args = concat(
    [
      "--served-model-name", var.served_model_name,
      "--kv-cache-dtype", var.kv_cache_dtype,
    ],
    var.reasoning_parser == null ? [] : ["--reasoning-parser", var.reasoning_parser],
    var.extra_args,
  )
}

resource "kubernetes_secret_v1" "vllm" {
  metadata {
    name      = "vllm-credentials"
    namespace = kubernetes_namespace_v1.vllm.metadata[0].name
  }

  data = merge(
    { api_key = local.api_key },
    var.hf_token == null ? {} : { hf_token = var.hf_token },
  )
}

# Not atomic, like the Ollama module: the first install downloads the model
# into the PVC and can take most of the timeout; a rollback would delete the
# chart-managed PVC and the partial download. upgrade_install lets a retried
# apply adopt a release that timed out instead of failing on a name clash.
resource "helm_release" "vllm" {
  name       = var.release_name
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
      model_name             = local.model_name
      image_repository       = var.image_repository
      image_tag              = var.image_tag
      model_repo             = var.model_repo
      max_model_len          = var.max_model_len
      max_num_seqs           = var.max_num_seqs
      gpu_memory_utilization = var.gpu_memory_utilization
      tool_call_parser       = var.tool_call_parser
      vllm_args              = local.vllm_args
      hami_full_gpu          = var.hami_full_gpu
      runtime_class_name     = var.runtime_class_name
      node_selector          = var.node_selector
      gpu_node_toleration    = var.gpu_node_toleration
      resources              = var.resources
      shm_size               = var.shm_size
      cache_size             = var.cache_size
      cache_storage_class    = var.cache_storage_class
      secret_name            = kubernetes_secret_v1.vllm.metadata[0].name
      has_hf_token           = var.hf_token != null
      startup_failures       = ceil(var.startup_timeout_seconds / 15)
      enable_monitoring      = var.enable_monitoring
    })
  ]
}
