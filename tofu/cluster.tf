# LKE Cluster with GPU nodes.
resource "linode_lke_cluster" "gpu_cluster" {
  label       = "${local.cluster_prefix}-lke-gpu"
  k8s_version = var.kubernetes_version
  region      = var.region
  tags        = var.tags

  pool {
    type  = var.gpu_node_type
    count = var.gpu_node_count

    autoscaler {
      min = var.autoscaler_min
      max = var.autoscaler_max
    }
  }

  control_plane {
    high_availability = var.ha_control_plane
  }
}
