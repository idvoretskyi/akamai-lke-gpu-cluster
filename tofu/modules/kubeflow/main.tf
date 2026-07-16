# Kubeflow Module — DEVIATES FROM THIS REPO'S HELM-MODULE CONVENTION.
#
# Upstream Kubeflow ("kubeflow/community-distribution") ships as Kustomize
# manifests, not a single Helm chart covering the full platform (only a
# handful of individual components have experimental Helm charts). To keep
# this a genuine "full Kubeflow" install per the project's own single-command
# path, this module shells out to `kustomize build | kubectl apply` instead of
# a `helm_release`. It is intentionally opt-in (`install_kubeflow = false` by
# default) and treated as a one-shot apply — OpenTofu does not track the
# resulting Kubernetes objects as state; re-running `tofu apply` re-applies
# the same manifests (idempotent), and `tofu destroy` simply tears down the
# whole LKE cluster (see AGENTS.md: cost is managed by destroy/recreate).

resource "local_sensitive_file" "kubeconfig" {
  filename = "${path.module}/.kubeconfig-kubeflow"
  content = templatefile("${path.module}/templates/kubeconfig.yaml.tftpl", {
    host        = var.k8s_host
    token       = var.k8s_token
    ca_cert_b64 = base64encode(var.k8s_cluster_ca_certificate)
  })
  file_permission = "0600"
}

resource "terraform_data" "install_kubeflow" {
  triggers_replace = {
    kubeflow_ref = var.kubeflow_ref
    k8s_host     = var.k8s_host
  }

  provisioner "local-exec" {
    # Absolute paths: the install script `cd`s into the cloned manifests
    # repo, so a relative kubeconfig/work-dir path passed in would no longer
    # resolve to the right file/directory after that `cd`.
    command     = "${abspath(path.module)}/scripts/install.sh ${abspath(local_sensitive_file.kubeconfig.filename)} ${var.kubeflow_ref} ${abspath(path.module)}/.work"
    interpreter = ["/usr/bin/env", "bash", "-c"]

    environment = {
      TIMEOUT_SECONDS = tostring(var.install_timeout)
    }
  }

  depends_on = [local_sensitive_file.kubeconfig]
}
