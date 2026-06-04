# Kubeflow Platform — installed from the upstream kustomize manifests.
#
# Kubeflow does not ship an official umbrella Helm chart; the supported install
# path is `kustomize build example | kubectl apply` against the pinned
# kubeflow/manifests repo, applied repeatedly until the cluster converges. This
# resource runs that flow via a guarded local-exec (the script preflights the
# required CLIs), mirroring the kubeconfig-merge pattern used elsewhere.
#
# Object store: the upstream minio Deployment is replaced with SeaweedFS via a
# kustomize overlay. The minio-service Service is repointed to SeaweedFS so all
# KFP consumers continue to work without configuration changes.
#
# Scheduling: when gpu_toleration_key is non-empty, a strategic-merge patch is
# applied to every Deployment and StatefulSet in the generated manifests (all
# namespaces), allowing those workloads to tolerate the GPU node taint and
# schedule onto the dedicated GPU pool when the system pool is under pressure.
resource "terraform_data" "kubeflow" {
  # Re-apply when the manifests version changes or the cluster is recreated.
  triggers_replace = {
    manifests_version  = var.manifests_version
    cluster_id         = var.cluster_id
    gpu_toleration_key = var.gpu_toleration_key
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/install-kubeflow.sh"
    environment = {
      LKE_KUBECONFIG_B64    = var.kubeconfig_b64
      KF_MANIFESTS_VERSION  = var.manifests_version
      KF_GPU_TOLERATION_KEY = var.gpu_toleration_key
    }
  }
}
