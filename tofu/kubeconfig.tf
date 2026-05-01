# Optionally merge the cluster kubeconfig into ~/.kube/config.
# Disable by setting merge_kubeconfig = false (e.g. in CI or when managing
# kubeconfig externally).
resource "terraform_data" "merge_kubeconfig" {
  count = var.merge_kubeconfig ? 1 : 0

  triggers_replace = {
    kubeconfig_content = base64decode(linode_lke_cluster.gpu_cluster.kubeconfig)
    cluster_id         = linode_lke_cluster.gpu_cluster.id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/merge-kubeconfig.sh"
    environment = {
      LKE_KUBECONFIG_B64 = linode_lke_cluster.gpu_cluster.kubeconfig
      LKE_CLUSTER_ID     = linode_lke_cluster.gpu_cluster.id
    }
  }
}
