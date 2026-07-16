# Advisory (non-blocking) checks — warnings only, never fail `tofu apply`.
# See AGENTS.md: OpenTofu `check` blocks (>= 1.9).

# Shared-CPU Linode plans known to be smaller than the ~9-10 GB Kubeflow +
# monitoring stack measurably uses (g6-standard-1/2/4 = 2/4/8 GB RAM).
# g6-standard-8 (32 GB) and up, or any dedicated-CPU/other plan, are assumed
# large enough and aren't flagged (this is advisory, not exhaustive).
locals {
  system_node_types_too_small_for_kubeflow = [
    "g6-standard-1",
    "g6-standard-2",
    "g6-standard-4",
  ]
}

check "hami_requires_gpu_operator" {
  assert {
    condition     = !var.install_hami || var.install_gpu_operator
    error_message = "install_hami = true has no effect without install_gpu_operator = true (HAMi relies on the operator's NVIDIA driver and container toolkit)."
  }
}

check "kubeflow_recommends_hami" {
  assert {
    condition     = !var.install_kubeflow || var.install_hami
    error_message = "install_kubeflow is enabled without install_hami — Kubeflow notebooks/pipelines will only be able to request whole GPUs instead of shared vGPU slices. Consider install_hami = true."
  }
}

check "kubeflow_recommends_larger_system_pool" {
  assert {
    condition     = !var.install_kubeflow || !contains(local.system_node_types_too_small_for_kubeflow, var.system_node_type)
    error_message = "install_kubeflow is enabled with system_node_type = '${var.system_node_type}' — the monitoring stack plus Kubeflow's system pods (Istio, Knative, Dex, dashboard, etc.) typically use ~9-10 GB in practice. Recommend system_node_type = 'g6-standard-8' (32 GB) or larger."
  }
}
