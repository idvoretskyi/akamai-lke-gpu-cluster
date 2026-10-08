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
  chart_version               = var.gpu_operator_version
  install_driver              = false # LKE GPU image ships the NVIDIA driver
  install_toolkit             = var.gpu_operator_install_toolkit
  device_plugin_enabled       = !var.install_hami
  enable_dcgm_exporter        = var.enable_gpu_monitoring
  enable_node_status_exporter = true
  node_selector               = local.system_node_selector
  gpu_node_toleration         = local.gpu_node_toleration
}

# HAMi Module — GPU virtualization/sharing.
# Splits each physical GPU into vGPU slices so multiple pods can share one
# GPU. Depends on the GPU Operator for the driver/toolkit; takes over the
# device-plugin + scheduling layer from it.
module "hami" {
  count  = var.install_hami ? 1 : 0
  source = "./modules/hami"

  namespace            = "hami-system"
  chart_version        = var.hami_version
  device_split_count   = var.hami_device_split_count
  node_selector        = local.system_node_selector
  nvidia_node_selector = local.gpu_node_labels
  gpu_node_toleration  = local.gpu_node_toleration

  # k8s_* used to restart the hami-scheduler Deployment after every
  # hami-scheduler-device ConfigMap patch (see modules/hami/main.tf) — always
  # required by the module regardless of default_gpu_memory's value, since
  # even resetting it to 0 needs the scheduler restarted to take effect.
  default_gpu_memory         = var.hami_default_gpu_memory
  k8s_host                   = local.k8s_auth.host
  k8s_token                  = local.k8s_auth.token
  k8s_cluster_ca_certificate = local.k8s_auth.cluster_ca_certificate

  depends_on = [module.gpu_operator]
}

# Metrics Server Module.
module "metrics_server" {
  count  = var.install_metrics_server ? 1 : 0
  source = "./modules/metrics-server"

  namespace     = "kube-system"
  chart_version = var.metrics_server_version
  node_selector = local.system_node_selector
}

# Kube Prometheus Stack Module.
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

# Ollama Module — serves local LLMs from the GPU pool.
# Pinned to the GPU nodes and given a slice of the GPU through HAMi's
# nvidia.com/gpumem (var.ollama_gpu_memory_mib), leaving headroom for other GPU pods. Without HAMi that resource doesn't exist (the pod would
# never schedule), so it is only requested when HAMi is installed.
module "ollama" {
  count  = var.install_ollama ? 1 : 0
  source = "./modules/ollama"

  namespace           = "ollama"
  chart_version       = var.ollama_version
  models              = var.ollama_models
  storage_size        = var.ollama_storage_size
  context_length      = var.ollama_context_length
  gpu_memory_mib      = var.install_hami ? var.ollama_gpu_memory_mib : null
  scheduler_name      = var.install_hami ? "hami-scheduler" : null
  node_selector       = local.gpu_node_labels
  gpu_node_toleration = local.gpu_node_toleration

  depends_on = [module.gpu_operator, module.hami]
}

# Argo Workflows Module — CNCF workflow engine. Runs on the system pool; its GPU
# steps are scheduled onto the GPU pool by the Workflow spec (toleration +
# nvidia.com/gpu limit), sharing the card with Ollama through HAMi.
module "argo_workflows" {
  count  = var.install_argo_workflows ? 1 : 0
  source = "./modules/argo-workflows"

  namespace              = "argo"
  chart_version          = var.argo_workflows_version
  enable_service_monitor = var.install_monitoring
  node_selector          = local.system_node_selector

  depends_on = [module.kube_prometheus_stack]
}

# Open WebUI Module — browser front-end for Ollama (opt-in, CPU-only).
module "open_webui" {
  count  = var.install_open_webui ? 1 : 0
  source = "./modules/open-webui"

  namespace     = "open-webui"
  chart_version = var.open_webui_version
  ollama_url    = "http://${try(module.ollama[0].service_name, "ollama")}.${try(module.ollama[0].namespace, "ollama")}.svc.cluster.local:11434"
  enable_signup = var.open_webui_enable_signup
  node_selector = local.system_node_selector

  depends_on = [module.ollama]
}

# OpenCost Module — Kubernetes cost monitoring.
# OpenCost depends on a Prometheus reachable in-cluster. The URL is sourced from
# the kube-prometheus-stack module output to avoid hardcoding the namespace and
# release name. When monitoring is disabled, null makes OpenCost fall back to
# the in-cluster default URL in modules/opencost/variables.tf, which won't
# resolve to anything real — see install_opencost's description in variables.tf.
module "opencost" {
  count  = var.install_opencost ? 1 : 0
  source = "./modules/opencost"

  namespace              = "opencost"
  chart_version          = var.opencost_version
  prometheus_url         = try(module.kube_prometheus_stack[0].prometheus_internal_url, null)
  enable_service_monitor = var.install_monitoring
  extra_labels           = { for t in var.tags : t => "true" }
  node_selector          = local.system_node_selector

  depends_on = [module.kube_prometheus_stack]
}

