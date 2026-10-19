# The platform: every Helm release, in install order.
#
#   metrics_server ─> kube_prometheus_stack ─┬─> cert_manager ─┬─> hami ──────────┐
#                                            │                 └─> envoy_gateway ─┴─> kserve (+ llmisvc) ─> argo_cd Application
#                                            └─> argo_cd ─────────────────────────────────────────────────┘
#
# Everything except the GPU operands runs on the system pool (the values/*.yaml
# files pin it). The model itself is not here: Argo CD deploys it from
# gitops/vllm (see the argo_cd section at the bottom).
#
# Releases are atomic, so a failed install or upgrade rolls back instead of
# leaving a half-installed chart behind.

# ─── HAMi ─────────────────────────────────────────────────────────────────────
# CNCF GPU device plugin and scheduler extension: advertises nvidia.com/gpu,
# can share a card between pods, and exports GPU metrics (ServiceMonitors).
# LKE GPU nodes already ship the NVIDIA driver and container toolkit. Installed
# after cert-manager, which issues the certificate of HAMi's admission webhook.

resource "kubernetes_namespace_v1" "hami" {
  metadata {
    name   = "hami-system"
    labels = merge(local.namespace_labels, { "app.kubernetes.io/name" = "hami" })
  }
}

resource "helm_release" "hami" {
  name       = "hami"
  repository = "https://project-hami.github.io/HAMi/"
  chart      = "hami"
  version    = local.chart_versions.hami
  namespace  = kubernetes_namespace_v1.hami.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/hami.yaml")]

  depends_on = [helm_release.cert_manager, helm_release.kube_prometheus_stack]
}

# ─── Metrics Server ───────────────────────────────────────────────────────────
# kubectl top, and the HPAs KServe creates.

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = local.chart_versions.metrics_server
  namespace  = "kube-system" # already exists

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/metrics-server.yaml")]
}

# ─── Prometheus + Grafana ─────────────────────────────────────────────────────
# Installed before the add-ons below so the ServiceMonitor CRD exists when
# cert-manager and Argo CD create their ServiceMonitors.

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name   = "monitoring"
    labels = merge(local.namespace_labels, { "app.kubernetes.io/name" = "kube-prometheus-stack" })
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = local.chart_versions.kube_prometheus_stack
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = 900

  values = [
    templatefile("${path.module}/values/kube-prometheus-stack.yaml.tftpl", {
      prometheus_retention    = local.prometheus_retention
      prometheus_storage_size = local.prometheus_storage_size
      grafana_storage_size    = local.grafana_storage_size
      # JSON string = valid YAML scalar, so any password survives intact.
      grafana_admin_password = jsonencode(var.grafana_admin_password)
      storage_class          = var.monitoring_storage_class
    })
  ]

  depends_on = [helm_release.metrics_server]
}

# ─── cert-manager ─────────────────────────────────────────────────────────────
# TLS certificates for KServe's admission webhooks.

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name   = "cert-manager"
    labels = merge(local.namespace_labels, { "app.kubernetes.io/name" = "cert-manager" })
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = local.chart_versions.cert_manager
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/cert-manager.yaml")]

  depends_on = [helm_release.kube_prometheus_stack]
}

# ─── Envoy Gateway ────────────────────────────────────────────────────────────
# Gateway API CRDs and implementation. Each Gateway gets an Envoy proxy whose
# Service is ClusterIP unless var.gateway_service_type says otherwise.

resource "kubernetes_namespace_v1" "envoy_gateway" {
  metadata {
    name   = "envoy-gateway-system"
    labels = merge(local.namespace_labels, { "app.kubernetes.io/name" = "envoy-gateway" })
  }
}

resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = local.chart_versions.envoy_gateway
  namespace  = kubernetes_namespace_v1.envoy_gateway.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/envoy-gateway.yaml")]

  depends_on = [helm_release.kube_prometheus_stack]
}

# The "envoy" GatewayClass and its EnvoyProxy settings. Custom resources whose
# CRDs come from the release above can't be planned with kubernetes_manifest on
# a fresh cluster, so they ship as a tiny local chart installed after it.
# KServe's chart hardcodes gatewayClassName: envoy, so the name is not a variable.
resource "helm_release" "gateway_class" {
  name      = "envoy-gateway-class"
  chart     = "${path.module}/charts/gateway-class"
  namespace = kubernetes_namespace_v1.envoy_gateway.metadata[0].name

  create_namespace = false
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [
    yamlencode({
      gatewayClassName = "envoy"
      serviceType      = var.gateway_service_type
      nodeSelector     = local.system_node_labels
    })
  ]

  depends_on = [helm_release.envoy_gateway]
}

# ─── KServe ───────────────────────────────────────────────────────────────────
# Control plane in Standard mode (plain Deployments, no Knative/Istio), routed
# through the Gateway API, plus the LLMInferenceService (llm-d) controller below. Three
# releases: the CRDs are separate so the controller can be upgraded or removed
# without touching every InferenceService in the cluster.

resource "kubernetes_namespace_v1" "kserve" {
  metadata {
    name = "kserve"
    labels = merge(local.namespace_labels, {
      "app.kubernetes.io/name" = "kserve"
      # KServe's webhooks skip namespaces labelled control-plane, so no
      # InferenceService may live here.
      "control-plane" = "kserve-controller-manager"
    })
  }
}

resource "helm_release" "kserve_crd" {
  name       = "kserve-crd"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = local.chart_versions.kserve
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout
}

resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-resources"
  version    = local.chart_versions.kserve
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/kserve.yaml")]

  depends_on = [
    helm_release.kserve_crd,
    helm_release.cert_manager,
    helm_release.gateway_class,
    helm_release.hami,
  ]
}

# LLMInferenceService (llm-d): KServe's API for LLM serving on upstream vLLM.
# Its CRDs and controller are separate charts; the shared resources (config,
# storage container, cert-manager issuer) already come from kserve-resources.
resource "helm_release" "kserve_llmisvc_crd" {
  name       = "kserve-llmisvc-crd"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-llmisvc-crd"
  version    = local.chart_versions.kserve
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout
}

resource "helm_release" "kserve_llmisvc" {
  name       = "kserve-llmisvc"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-llmisvc-resources"
  version    = local.chart_versions.kserve
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/kserve-llmisvc.yaml")]

  depends_on = [helm_release.kserve_llmisvc_crd, helm_release.kserve]
}

# ─── Argo CD ──────────────────────────────────────────────────────────────────
# GitOps. Owns the model: the "vllm" Application syncs gitops/vllm from this
# repository, so changing the model is a Git commit, not a `tofu apply`.

resource "kubernetes_namespace_v1" "argo_cd" {
  metadata {
    name   = "argocd"
    labels = merge(local.namespace_labels, { "app.kubernetes.io/name" = "argo-cd" })
  }
}

resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = local.chart_versions.argo_cd
  namespace  = kubernetes_namespace_v1.argo_cd.metadata[0].name

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [file("${path.module}/values/argo-cd.yaml")]

  depends_on = [helm_release.kube_prometheus_stack]
}

# The bootstrap Application (a custom resource, hence a local chart, as above).
# It carries Argo CD's resources finalizer, so destroying this release deletes
# the InferenceService it synced. That is why it depends on KServe: on
# `tofu destroy` the InferenceService must go while KServe still runs.
resource "helm_release" "applications" {
  name      = "argo-cd-applications"
  chart     = "${path.module}/charts/argo-cd-apps"
  namespace = kubernetes_namespace_v1.argo_cd.metadata[0].name

  create_namespace = false
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 5
  timeout          = local.helm_timeout

  values = [
    yamlencode({
      applications = [{
        name            = "vllm"
        namespace       = local.model_namespace
        repo_url        = var.gitops_repo_url
        target_revision = var.gitops_target_revision
        path            = local.gitops_path
      }]
    })
  ]

  depends_on = [helm_release.argo_cd, helm_release.kserve_llmisvc]
}
