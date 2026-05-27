# GPU Operator Module.
module "gpu_operator" {
  count  = var.install_gpu_operator ? 1 : 0
  source = "./modules/gpu-operator"

  namespace                   = "gpu-operator"
  gpu_operator_version        = var.gpu_operator_version
  install_driver              = true
  enable_dcgm_exporter        = var.enable_gpu_monitoring
  enable_node_status_exporter = true
}

# Metrics Server Module.
module "metrics_server" {
  count  = var.install_metrics_server ? 1 : 0
  source = "./modules/metrics-server"

  namespace = "kube-system"
}

# Kube Prometheus Stack Module.
module "kube_prometheus_stack" {
  count  = var.install_monitoring ? 1 : 0
  source = "./modules/kube-prometheus-stack"

  namespace                 = "monitoring"
  grafana_admin_password    = var.grafana_admin_password
  prometheus_retention      = var.prometheus_retention
  prometheus_storage_size   = var.prometheus_storage_size
  alertmanager_storage_size = var.alertmanager_storage_size
  grafana_storage_size      = var.grafana_storage_size
  enable_gpu_monitoring     = var.enable_gpu_monitoring && var.install_gpu_operator
  prometheus_resources      = var.prometheus_resources
  grafana_resources         = var.grafana_resources
  alertmanager_resources    = var.alertmanager_resources

  depends_on = [module.gpu_operator, module.metrics_server]
}

# OpenCost Module — Kubernetes cost monitoring.
# OpenCost depends on a Prometheus reachable in-cluster. The URL is sourced from
# the kube-prometheus-stack module output to avoid hardcoding the namespace and
# release name. When monitoring is disabled, OpenCost should also be disabled
# (see validation in variables.tf and the check in checks.tf).
module "opencost" {
  count  = var.install_opencost ? 1 : 0
  source = "./modules/opencost"

  namespace              = "opencost"
  opencost_chart_version = var.opencost_chart_version
  prometheus_url         = try(module.kube_prometheus_stack[0].prometheus_internal_url, "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090")
  enable_service_monitor = var.install_monitoring
  extra_labels           = { for t in var.tags : t => "true" }

  depends_on = [module.kube_prometheus_stack]
}
