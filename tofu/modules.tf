# GPU Operator Module.
# The controller is pinned to the system pool; the GPU operands (driver,
# toolkit, device-plugin, DCGM, …) keep scheduling onto GPU nodes via the taint
# toleration so the GPU pool stays dedicated to GPU work. The stock device
# plugin is disabled when HAMi is installed — HAMi takes over device-plugin
# and scheduling duties instead.
module "gpu_operator" {
  count  = var.install_gpu_operator ? 1 : 0
  source = "./modules/gpu-operator"

  namespace                   = "gpu-operator"
  gpu_operator_version        = var.gpu_operator_version
  install_driver              = true
  device_plugin_enabled       = !var.install_hami
  enable_dcgm_exporter        = var.enable_gpu_monitoring
  enable_node_status_exporter = true
  controller_node_selector    = local.system_node_selector
  gpu_node_toleration         = var.dedicate_gpu_nodes ? local.gpu_node_taint : null
}

# HAMi Module — GPU virtualization/sharing.
# Splits each physical GPU into vGPU slices so multiple pods can share one
# GPU. Depends on the GPU Operator for the driver/toolkit; takes over the
# device-plugin + scheduling layer from it.
module "hami" {
  count  = var.install_hami ? 1 : 0
  source = "./modules/hami"

  namespace            = "hami-system"
  hami_version         = var.hami_version
  device_split_count   = var.hami_device_split_count
  node_selector        = local.system_node_selector
  nvidia_node_selector = local.gpu_node_labels
  gpu_node_toleration  = var.dedicate_gpu_nodes ? local.gpu_node_taint : null

  depends_on = [module.gpu_operator]
}

# Kubeflow Module — full Kubeflow Platform (opt-in, heavy).
# Installed via kustomize + kubectl apply (see modules/kubeflow/README.md for
# why this deviates from the Helm-module convention used elsewhere).
module "kubeflow" {
  count  = var.install_kubeflow ? 1 : 0
  source = "./modules/kubeflow"

  kubeflow_ref               = var.kubeflow_ref
  k8s_host                   = local.k8s_auth.host
  k8s_token                  = local.k8s_auth.token
  k8s_cluster_ca_certificate = local.k8s_auth.cluster_ca_certificate

  depends_on = [module.hami, module.gpu_operator]
}

# Metrics Server Module.
module "metrics_server" {
  count  = var.install_metrics_server ? 1 : 0
  source = "./modules/metrics-server"

  namespace     = "kube-system"
  node_selector = local.system_node_selector
}

# Kube Prometheus Stack Module.
module "kube_prometheus_stack" {
  count  = var.install_monitoring ? 1 : 0
  source = "./modules/kube-prometheus-stack"

  namespace               = "monitoring"
  grafana_admin_password  = var.grafana_admin_password
  prometheus_retention    = var.prometheus_retention
  prometheus_storage_size = var.prometheus_storage_size
  grafana_storage_size    = var.grafana_storage_size
  enable_gpu_monitoring   = var.enable_gpu_monitoring && var.install_gpu_operator
  prometheus_resources    = var.prometheus_resources
  grafana_resources       = var.grafana_resources
  node_selector           = local.system_node_selector

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
  node_selector          = local.system_node_selector

  depends_on = [module.kube_prometheus_stack]
}

