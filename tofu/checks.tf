# Advisory (non-blocking) checks — warnings only, never fail `tofu apply`.
# See AGENTS.md: OpenTofu `check` blocks (>= 1.9).
#
# Note: install_hami requiring install_gpu_operator is a hard error (variable
# validation on install_hami in variables.tf), not just advisory here — HAMi
# is entirely non-functional without the operator's driver/toolkit, so it's
# treated as a real misconfiguration rather than a "you might want to
# reconsider" suggestion.

check "opencost_recommends_monitoring" {
  assert {
    condition     = !var.install_opencost || var.install_monitoring
    error_message = "install_opencost is enabled without install_monitoring — OpenCost has no in-cluster Prometheus to scrape and falls back to a URL that won't resolve to anything real. Consider install_monitoring = true."
  }
}

check "gpu_monitoring_requires_gpu_operator" {
  assert {
    condition     = !var.enable_gpu_monitoring || var.install_gpu_operator
    error_message = "enable_gpu_monitoring is enabled without install_gpu_operator — there is no DCGM exporter to produce GPU metrics, so this setting has no effect. Consider install_gpu_operator = true."
  }
}

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
