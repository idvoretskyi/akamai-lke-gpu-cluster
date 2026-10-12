# Create namespace for Envoy Gateway (controller + the Envoy proxy pods it
# provisions for each Gateway).
resource "kubernetes_namespace_v1" "envoy_gateway" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "envoy-gateway"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Envoy Gateway — Gateway API implementation. The chart also installs the
# Gateway API CRDs (crds.enabled), so no separate CRD step is needed.
resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.envoy_gateway.metadata[0].name

  create_namespace = false

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      node_selector = var.node_selector
    })
  ]
}

# GatewayClass + EnvoyProxy. These are custom resources whose CRDs only exist
# after the release above is installed, so they can't be planned with
# kubernetes_manifest on a fresh cluster; a tiny local chart installed after
# the controller sidesteps that.
resource "helm_release" "gateway_class" {
  name      = "envoy-gateway-class"
  chart     = "${path.module}/chart"
  namespace = kubernetes_namespace_v1.envoy_gateway.metadata[0].name

  create_namespace = false

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  max_history     = 5
  timeout         = var.timeout

  values = [
    yamlencode({
      gatewayClassName = var.gateway_class_name
      serviceType      = var.service_type
      nodeSelector     = var.node_selector
    })
  ]

  depends_on = [helm_release.envoy_gateway]
}
