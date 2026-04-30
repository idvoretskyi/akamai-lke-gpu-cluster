# Cross-variable validation: gpu_node_count must fall within the autoscaler range.
resource "terraform_data" "validation_autoscaling" {
  lifecycle {
    precondition {
      condition     = var.autoscaler_min <= var.gpu_node_count && var.gpu_node_count <= var.autoscaler_max
      error_message = "gpu_node_count (${var.gpu_node_count}) must be between autoscaler_min (${var.autoscaler_min}) and autoscaler_max (${var.autoscaler_max})."
    }
  }
}
