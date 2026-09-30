# llama.cpp llama-server: an alternative GPU model server for GGUF models,
# including dense models too large for vLLM on one 20 GB card (layers or FFN
# weights can stay in host RAM). There is no maintained llama-server chart,
# so this wraps the generic bjw-s app-template chart.

resource "kubernetes_namespace_v1" "llamacpp" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "llamacpp"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

resource "random_password" "api_key" {
  count   = var.api_key == null ? 1 : 0
  length  = 40
  special = false
}

locals {
  api_key      = var.api_key != null ? var.api_key : random_password.api_key[0].result
  service_name = var.release_name
  service_port = 8080

  server_args = concat(
    [
      "--host", "0.0.0.0",
      "--port", tostring(local.service_port),
      "-hf", var.gguf_repo,
      "--alias", var.served_model_name,
      "-c", tostring(var.context_size),
      "-ngl", "99",
      "-fa", "on",
      "-ctk", var.kv_cache_type,
      "-ctv", var.kv_cache_type,
      "-np", tostring(var.parallel),
      "--jinja",
      "--no-mmproj",
      "--metrics",
    ],
    var.n_cpu_moe > 0 ? ["--n-cpu-moe", tostring(var.n_cpu_moe)] : [],
    var.n_cpu_ffn > 0 ? ["--n-cpu-ffn", tostring(var.n_cpu_ffn)] : [],
    var.extra_args,
  )
}

resource "kubernetes_secret_v1" "llamacpp" {
  metadata {
    name      = "llamacpp-credentials"
    namespace = kubernetes_namespace_v1.llamacpp.metadata[0].name
  }

  data = merge(
    { api_key = local.api_key },
    var.hf_token == null ? {} : { hf_token = var.hf_token },
  )
}

# Not atomic, for the same reason as vLLM and Ollama: the first start
# downloads the GGUF into the PVC, and a rollback would delete it.
resource "helm_release" "llamacpp" {
  name       = var.release_name
  repository = "https://bjw-s-labs.github.io/helm-charts"
  chart      = "app-template"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.llamacpp.metadata[0].name

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
      image_repository    = var.image_repository
      image_tag           = var.image_tag
      server_args         = local.server_args
      secret_name         = kubernetes_secret_v1.llamacpp.metadata[0].name
      has_hf_token        = var.hf_token != null
      hami_full_gpu       = var.hami_full_gpu
      runtime_class_name  = var.runtime_class_name
      node_selector       = var.node_selector
      gpu_node_toleration = var.gpu_node_toleration
      resources           = var.resources
      cache_size          = var.cache_size
      cache_storage_class = var.cache_storage_class
      service_port        = local.service_port
      startup_failures    = ceil(var.startup_timeout_seconds / 15)
      enable_monitoring   = var.enable_monitoring
    })
  ]
}
