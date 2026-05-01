# Advisory checks — non-blocking warnings evaluated after plan.
# These use OpenTofu check blocks (requires >= 1.9).

# Warn if the user has selected a GPU plan other than the cheapest available.
check "cheapest_gpu_plan" {
  assert {
    condition     = var.gpu_node_type == "g2-gpu-rtx4000a1-s"
    error_message = "gpu_node_type '${var.gpu_node_type}' is not the cheapest Linode GPU SKU. The cheapest plan is 'g2-gpu-rtx4000a1-s' (NVIDIA RTX 4000 Ada x1 Small, ~$0.52/hr). Override intentionally if a larger GPU is needed."
  }
}

# Warn if HA control plane is disabled but autoscaler_max > 1 (production-like scale).
check "ha_recommended_for_scale" {
  assert {
    condition     = var.autoscaler_max <= 2 || var.ha_control_plane == true
    error_message = "autoscaler_max is ${var.autoscaler_max} but ha_control_plane is false. Consider enabling HA control plane for production-scale clusters."
  }
}
