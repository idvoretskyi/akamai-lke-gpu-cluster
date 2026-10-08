# Platform layer. Everything except the GPU operands runs on the system pool
# (local.system_node_selector); the GPU pool is reserved for model servers.
#
# Dependency graph (install order; destroy runs in reverse):
#
#   gpu_operator ─┐
#   metrics_server┴─> kube_prometheus_stack ─┐
#   cert_manager ─────────────────────────────┼─> kserve ─> argo_cd (Application "vllm")
#   envoy_gateway ────────────────────────────┘
#
# kube-prometheus-stack goes first among the add-ons so its ServiceMonitor CRD
# exists when the others ask for ServiceMonitors.

# GPU Operator — device plugin, GPU feature discovery, DCGM exporter. The LKE
# GPU image already ships the driver and container toolkit.
module "gpu_operator" {
  count  = var.install_gpu_operator ? 1 : 0
  source = "./modules/gpu-operator"

  namespace                   = "gpu-operator"
  chart_version               = var.gpu_operator_version
  install_driver              = false # LKE GPU image ships the NVIDIA driver
  install_toolkit             = var.gpu_operator_install_toolkit
  device_plugin_enabled       = true
  enable_dcgm_exporter        = var.enable_gpu_monitoring
  enable_node_status_exporter = true
  node_selector               = local.system_node_selector
  gpu_node_toleration         = local.gpu_node_toleration
}

# Metrics Server — kubectl top and HPA (KServe Standard mode creates HPAs).
module "metrics_server" {
  count  = var.install_metrics_server ? 1 : 0
  source = "./modules/metrics-server"

  namespace     = "kube-system"
  chart_version = var.metrics_server_version
  node_selector = local.system_node_selector
}

# kube-prometheus-stack — Prometheus + Grafana. Picks up every ServiceMonitor
# in the cluster, plus the DCGM exporter's GPU metrics.
module "kube_prometheus_stack" {
  count  = var.install_monitoring ? 1 : 0
  source = "./modules/kube-prometheus-stack"

  namespace               = "monitoring"
  chart_version           = var.kube_prometheus_stack_version
  grafana_admin_password  = var.grafana_admin_password
  prometheus_retention    = var.prometheus_retention
  prometheus_storage_size = var.prometheus_storage_size
  grafana_storage_size    = var.grafana_storage_size
  enable_gpu_monitoring   = local.gpu_monitoring_enabled
  dcgm_exporter_namespace = try(module.gpu_operator[0].namespace, "gpu-operator")
  prometheus_resources    = var.prometheus_resources
  grafana_resources       = var.grafana_resources
  node_selector           = local.system_node_selector

  depends_on = [module.gpu_operator, module.metrics_server]
}

# cert-manager — TLS for KServe's admission webhooks.
module "cert_manager" {
  count  = var.install_kserve ? 1 : 0
  source = "./modules/cert-manager"

  namespace              = "cert-manager"
  chart_version          = var.cert_manager_version
  node_selector          = local.system_node_selector
  enable_service_monitor = var.install_monitoring

  depends_on = [module.kube_prometheus_stack]
}

# Envoy Gateway — Gateway API CRDs + implementation, and the "envoy"
# GatewayClass that KServe's Gateway uses. Private (ClusterIP) by default.
module "envoy_gateway" {
  count  = var.install_kserve ? 1 : 0
  source = "./modules/envoy-gateway"

  namespace     = "envoy-gateway-system"
  chart_version = var.envoy_gateway_version
  service_type  = var.gateway_service_type
  node_selector = local.system_node_selector

  depends_on = [module.kube_prometheus_stack]
}

# KServe — model serving control plane (Standard mode, Gateway API) and the
# vLLM-backed Hugging Face serving runtime.
module "kserve" {
  count  = var.install_kserve ? 1 : 0
  source = "./modules/kserve"

  namespace      = "kserve"
  chart_version  = var.kserve_version
  ingress_domain = var.kserve_ingress_domain
  node_selector  = local.system_node_selector

  depends_on = [module.cert_manager, module.envoy_gateway, module.gpu_operator]
}

# Argo CD — GitOps. Owns the model workloads: the "vllm" Application syncs
# gitops/vllm (the InferenceService) from this repository.
module "argo_cd" {
  count  = var.install_argo_cd ? 1 : 0
  source = "./modules/argo-cd"

  namespace              = "argocd"
  chart_version          = var.argo_cd_version
  node_selector          = local.system_node_selector
  enable_service_monitor = var.install_monitoring

  applications = var.install_kserve && var.gitops_path != "" ? [{
    name            = "vllm"
    namespace       = var.model_namespace
    repo_url        = var.gitops_repo_url
    target_revision = var.gitops_target_revision
    path            = var.gitops_path
  }] : []

  # The Application must be deleted (and its InferenceService with it) before
  # KServe goes away on destroy, so Argo CD depends on KServe.
  depends_on = [module.kube_prometheus_stack, module.kserve]
}
