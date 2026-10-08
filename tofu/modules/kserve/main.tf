# Create namespace for the KServe control plane (controller, webhooks, the
# shared kserve-ingress-gateway Gateway).
resource "kubernetes_namespace_v1" "kserve" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "kserve"
      "app.kubernetes.io/managed-by" = "opentofu"
      # KServe's webhooks skip namespaces labelled control-plane, so no
      # InferenceService may live here.
      "control-plane" = "kserve-controller-manager"
    }
  }
}

# 1/3 — KServe CRDs (InferenceService, ServingRuntime, ...). A separate release
# so the controller chart can be upgraded or removed without touching the CRDs
# (and therefore every InferenceService in the cluster).
resource "helm_release" "kserve_crd" {
  name       = "kserve-crd"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout
}

# 2/3 — KServe controller in Standard (raw Kubernetes Deployment) mode, routed
# through the Gateway API. createGateway makes the chart create the shared
# Gateway "kserve-ingress-gateway" (class "envoy") that every
# InferenceService's HTTPRoute attaches to.
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-resources"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      namespace                        = kubernetes_namespace_v1.kserve.metadata[0].name
      domain                           = var.ingress_domain
      storage_initializer_memory_limit = var.storage_initializer_memory_limit
      node_selector                    = var.node_selector
    })
  ]

  depends_on = [helm_release.kserve_crd]
}

# 3/3 — ClusterServingRuntimes. Only the Hugging Face runtime matters here: it
# is KServe's vLLM-backed LLM server. Its default image is the CPU build, so the
# tag is pinned to the CUDA ("-gpu") build, and /dev/shm is enlarged for vLLM.
resource "helm_release" "runtimes" {
  name       = "kserve-runtime-configs"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-runtime-configs"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    yamlencode({
      kserve = {
        servingruntime = {
          enabled = true
          huggingfaceserver = {
            tag    = "${var.chart_version}-gpu"
            devShm = { enabled = true, sizeLimit = var.vllm_shm_size }
          }
        }
      }
    })
  ]

  depends_on = [helm_release.kserve]
}
