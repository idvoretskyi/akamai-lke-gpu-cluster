# Kubeflow Platform — installed from the upstream kustomize manifests.
#
# Kubeflow does not ship an official umbrella Helm chart; the supported install
# path is `kustomize build example | kubectl apply` against the pinned
# kubeflow/manifests repo, applied repeatedly until the cluster converges. This
# resource runs that flow via a guarded local-exec (the script preflights the
# required CLIs), mirroring the kubeconfig-merge pattern used elsewhere.
#
# Scheduling note: every Kubeflow control-plane pod runs without a toleration
# for the GPU node taint (nvidia.com/gpu=present:NoSchedule), so the scheduler
# keeps them off the dedicated GPU nodes and on the system pool automatically.
# GPU pipeline steps opt back onto GPU nodes by adding the matching toleration
# (see examples/kubeflow-pipelines).
resource "terraform_data" "kubeflow" {
  # Re-apply when the manifests version changes or the cluster is recreated.
  triggers_replace = {
    manifests_version = var.manifests_version
    cluster_id        = var.cluster_id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/install-kubeflow.sh"
    environment = {
      LKE_KUBECONFIG_B64   = var.kubeconfig_b64
      KF_MANIFESTS_VERSION = var.manifests_version
    }
  }
}
