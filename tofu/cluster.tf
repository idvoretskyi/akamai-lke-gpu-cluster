# LKE Cluster with a dedicated system pool and a GPU pool.
#
# The cluster runs two node pools:
#   * system — a CPU pool that hosts cluster "system" workloads (monitoring,
#     metrics-server, GPU Operator controller, cert-manager, Envoy Gateway,
#     KServe controller, Argo CD).
#   * gpu    — the (expensive) GPU pool, tainted so it is reserved for model servers (the vLLM InferenceService).
#
# Autoscaling is intentionally disabled on both pools. Fixed node counts keep
# costs fully predictable — no surprise scale-up events on expensive GPU nodes.
resource "linode_lke_cluster" "gpu_cluster" {
  label       = "${local.cluster_prefix}-lke-gpu"
  k8s_version = var.kubernetes_version
  region      = var.region
  tags        = local.tags

  # Dedicated system pool — keeps system/monitoring workloads off the GPU nodes.
  pool {
    type   = var.system_node_type
    count  = local.system_node_count
    labels = local.system_node_labels
  }

  # GPU pool — reserved for GPU-intensive workloads via the taint below.
  pool {
    type   = var.gpu_node_type
    count  = var.gpu_node_count
    labels = local.gpu_node_labels

    taint {
      key    = local.gpu_node_taint.key
      value  = local.gpu_node_taint.value
      effect = local.gpu_node_taint.effect
    }
  }

  control_plane {
    high_availability = local.ha_control_plane
  }
}
