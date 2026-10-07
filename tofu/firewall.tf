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

  # Allow all intra-cluster TCP: control-plane→kubelet (10250), API server→webhooks (443/9443),
  # node↔node, pod↔pod.  Without this the Linode Cloud Firewall drops these packets and
  # webhook admission (e.g. HAMi's) times out and kubectl logs/exec fail.
  inbound {
    label    = "allow-intra-cluster-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = local.intra_cluster_cidrs
  }

  inbound {
    label    = "allow-intra-cluster-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "1-65535"
    ipv4     = local.intra_cluster_cidrs
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    for p in linode_lke_cluster.gpu_cluster.pool : [
      for n in p.nodes : n.instance_id
    ]
  ])
}
