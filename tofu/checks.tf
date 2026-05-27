# Advisory checks — non-blocking warnings evaluated after plan.
# These use OpenTofu check blocks (requires >= 1.9).

# A small allowlist of known cost-efficient Linode GPU SKUs. Update as Linode
# adds cheaper plans. Set var.warn_on_non_default_gpu = false to silence.
locals {
  cost_efficient_gpu_plans = [
    "g2-gpu-rtx4000a1-s", # RTX 4000 Ada x1 Small, ~$0.52/hr (cheapest as of 2025)
  ]

  # Coarse $/month estimate per known GPU SKU (24/7 operation).
  # Keep conservative; used only by the cost-ceiling advisory check.
  gpu_plan_monthly_cost = {
    "g2-gpu-rtx4000a1-s" = 380
    "g2-gpu-rtx4000a1-m" = 760
    "g2-gpu-rtx4000a1-l" = 1520
  }

  estimated_monthly_cost = (
    lookup(local.gpu_plan_monthly_cost, var.gpu_node_type, 0) * var.gpu_node_count
    + (var.ha_control_plane ? 60 : 0)
  )
}

# Warn if the user has selected a GPU plan outside the known cost-efficient set.
check "cost_efficient_gpu_plan" {
  assert {
    condition     = !var.warn_on_non_default_gpu || contains(local.cost_efficient_gpu_plans, var.gpu_node_type)
    error_message = "gpu_node_type '${var.gpu_node_type}' is not in the known cost-efficient GPU allowlist (${join(", ", local.cost_efficient_gpu_plans)}). This is informational; override intentionally if a larger GPU is required, or set warn_on_non_default_gpu = false to silence."
  }
}

# Warn if HA control plane is disabled but autoscaler_max > 1 (production-like scale).
check "ha_recommended_for_scale" {
  assert {
    condition     = var.autoscaler_max <= 2 || var.ha_control_plane == true
    error_message = "autoscaler_max is ${var.autoscaler_max} but ha_control_plane is false. Consider enabling HA control plane for production-scale clusters."
  }
}

# Warn if OpenCost is enabled without the monitoring stack — OpenCost requires
# an in-cluster Prometheus to function. The fallback URL in modules.tf will not
# resolve, and OpenCost queries will fail.
check "opencost_requires_monitoring" {
  assert {
    condition     = !var.install_opencost || var.install_monitoring
    error_message = "install_opencost = true requires install_monitoring = true (OpenCost queries an in-cluster Prometheus). Set install_opencost = false or enable monitoring."
  }
}

# Warn if estimated monthly cost exceeds the configured ceiling.
check "cost_ceiling" {
  assert {
    condition     = local.estimated_monthly_cost <= var.cost_ceiling_usd_per_month
    error_message = "Estimated monthly cost ~${local.estimated_monthly_cost} USD exceeds ceiling ${var.cost_ceiling_usd_per_month} USD/month (gpu_node_type=${var.gpu_node_type}, gpu_node_count=${var.gpu_node_count}, ha_control_plane=${var.ha_control_plane}). Storage and egress are not included. Raise the ceiling or reduce scale."
  }
}
