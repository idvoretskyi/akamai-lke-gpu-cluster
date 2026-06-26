# LKE Cluster with a dedicated system pool and a GPU pool.
#
# The cluster runs two node pools:
#   * system — a CPU pool that hosts cluster "system" workloads (monitoring,
#     metrics-server, OpenCost, GPU Operator controller). g6-standard-4 is
#     recommended when adding Kubeflow — the monitoring stack + Kubeflow system
#     pods exceed 4 GB.
#   * gpu    — the (expensive) GPU pool, tainted when var.dedicate_gpu_nodes is
#     true so it is reserved purely for GPU-intensive workloads.
#
# Autoscaling is intentionally disabled on both pools. Fixed node counts keep
# costs fully predictable — no surprise scale-up events on expensive GPU nodes.
resource "linode_lke_cluster" "gpu_cluster" {
  label       = "${local.cluster_prefix}-lke-gpu"
  k8s_version = var.kubernetes_version
  region      = var.region
  tags        = var.tags

  # Dedicated system pool — keeps system/monitoring workloads off the GPU nodes.
  pool {
    type   = var.system_node_type
    count  = var.system_node_count
    labels = local.system_node_labels
  }

  # GPU pool — reserved for GPU-intensive workloads via the taint below.
  pool {
    type   = var.gpu_node_type
    count  = var.gpu_node_count
    labels = local.gpu_node_labels

    dynamic "taint" {
      for_each = var.dedicate_gpu_nodes ? [local.gpu_node_taint] : []
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  control_plane {
    high_availability = var.ha_control_plane
  }
}
