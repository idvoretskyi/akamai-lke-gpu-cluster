# Advisory (non-blocking) checks — warnings only, never fail `tofu apply`.
# See AGENTS.md: OpenTofu `check` blocks (>= 1.9).

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
    condition     = !var.install_kubeflow || var.system_node_type != "g6-standard-2"
    error_message = "install_kubeflow is enabled with system_node_type = 'g6-standard-2' — the monitoring stack plus Kubeflow's system pods (Istio, Knative, Dex, dashboard, etc.) typically use ~9-10 GB in practice. Recommend system_node_type = 'g6-standard-8' (32 GB) or larger."
  }
}
