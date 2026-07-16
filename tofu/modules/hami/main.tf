# Create namespace for HAMi.
resource "kubernetes_namespace_v1" "hami" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "hami"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }
}

# Install HAMi (Heterogeneous AI Computing Virtualization middleware) via Helm.
# HAMi replaces the NVIDIA device plugin with a vGPU-aware one, so a single
# physical GPU can be split into multiple schedulable slices (by count and/or
# memory), and adds a scheduler extender + webhook that enforce the split.
resource "helm_release" "hami" {
  name       = "hami"
  repository = "https://project-hami.github.io/HAMi"
  chart      = "hami"
  version    = var.hami_version
  namespace  = kubernetes_namespace_v1.hami.metadata[0].name

  create_namespace = false
  depends_on       = [kubernetes_namespace_v1.hami]

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      device_split_count     = var.device_split_count
      device_memory_scaling  = var.device_memory_scaling
      device_core_scaling    = var.device_core_scaling
      scheduler_policy       = var.scheduler_policy
      node_selector          = var.node_selector
      gpu_node_toleration    = var.gpu_node_toleration
      nvidia_node_selector   = var.nvidia_node_selector
      runtime_class_name     = var.runtime_class_name
      nvidia_driver_root     = var.nvidia_driver_root
      wait_for_toolkit_ready = var.wait_for_toolkit_ready
      scheduler_leader_elect = var.scheduler_leader_elect
    })
  ]
}

# HAMi chart v2.9.0 hardcodes `nvidia.defaultMemory: 0` in the
# hami-scheduler-device ConfigMap template — there is no Helm value for it
# (see templates/scheduler/device-configmap.yaml upstream). defaultMemory
# controls the vGPU memory slice a Pod gets when it requests
# `nvidia.com/gpu` WITHOUT an explicit `nvidia.com/gpumem` limit — 0 means
# "give the whole physical GPU", which defeats the point of virtualization
# for any workload (e.g. most Kubeflow-orchestrated pods) that can't easily
# set that extra resource key.
#
# Authors the ConfigMap's data directly (rather than reading Helm's rendered
# version and merging in the one field we want) because the Terraform
# Kubernetes provider's `kubernetes_config_map_v1` data source has a known
# bug with map keys containing dots — like "device-config.yaml" — silently
# returning a null `data` map. Non-NVIDIA vendor sections the chart ships
# (Cambricon, Ascend, etc.) are omitted; this cluster is NVIDIA-only and
# HAMi tolerates their absence.
#
# Every `tofu apply` re-applies this after Helm's own apply runs (see
# depends_on), so it converges even though Helm has no idea this field is
# being overridden out-of-band.
resource "kubernetes_config_map_v1_data" "device_config_default_memory" {
  count = var.default_gpu_memory > 0 ? 1 : 0

  metadata {
    name      = "${helm_release.hami.name}-scheduler-device"
    namespace = kubernetes_namespace_v1.hami.metadata[0].name
  }

  force = true

  data = {
    "device-config.yaml" = templatefile("${path.module}/templates/device-config.yaml.tftpl", {
      default_gpu_memory    = var.default_gpu_memory
      device_split_count    = var.device_split_count
      device_memory_scaling = var.device_memory_scaling
      device_core_scaling   = var.device_core_scaling
      runtime_class_name    = var.runtime_class_name
    })
  }

  depends_on = [helm_release.hami]
}

# HAMi's scheduler only reads hami-scheduler-device at process startup, not
# on ConfigMap change (kubelet updates the mounted file, but the running
# process doesn't watch it) — so the patch above has no effect until the
# scheduler restarts. Do that here, right after the patch, using a scratch
# kubeconfig (same approach as modules/kubeflow) since this module otherwise
# only talks to the cluster via the Helm/Kubernetes Terraform providers,
# neither of which can trigger a Deployment rollout restart directly.
resource "local_sensitive_file" "kubeconfig" {
  count = var.default_gpu_memory > 0 ? 1 : 0

  filename = "${path.module}/.kubeconfig-hami"
  content = templatefile("${path.module}/templates/kubeconfig.yaml.tftpl", {
    host        = var.k8s_host
    token       = var.k8s_token
    ca_cert_b64 = base64encode(var.k8s_cluster_ca_certificate)
  })
  file_permission = "0600"
}

resource "terraform_data" "restart_scheduler" {
  count = var.default_gpu_memory > 0 ? 1 : 0

  triggers_replace = {
    # Re-run whenever the patched ConfigMap content actually changes.
    device_config_sha = sha256(kubernetes_config_map_v1_data.device_config_default_memory[0].data["device-config.yaml"])
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --kubeconfig ${abspath(local_sensitive_file.kubeconfig[0].filename)} \
        rollout restart deployment/${helm_release.hami.name}-scheduler -n ${kubernetes_namespace_v1.hami.metadata[0].name}
      kubectl --kubeconfig ${abspath(local_sensitive_file.kubeconfig[0].filename)} \
        rollout status deployment/${helm_release.hami.name}-scheduler -n ${kubernetes_namespace_v1.hami.metadata[0].name} --timeout=120s
    EOT
  }

  depends_on = [
    kubernetes_config_map_v1_data.device_config_default_memory,
    local_sensitive_file.kubeconfig,
  ]
}
