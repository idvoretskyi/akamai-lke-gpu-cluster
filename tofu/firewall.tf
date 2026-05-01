# Firewall for LKE cluster.
resource "linode_firewall" "lke_firewall" {
  label = "${local.cluster_prefix}-lke-firewall"
  tags  = var.tags

  inbound {
    label    = "allow-kubectl"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = var.allowed_kubectl_ips
  }

  inbound {
    label    = "allow-monitoring-ui"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80,443,3000,9090"
    ipv4     = var.allowed_monitoring_ips
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [for node in linode_lke_cluster.gpu_cluster.pool[0].nodes : node.instance_id]

  depends_on = [linode_lke_cluster.gpu_cluster]
}
