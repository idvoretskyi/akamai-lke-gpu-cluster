# Advisory (non-blocking) checks — warnings only, never fail `tofu apply`.
# See AGENTS.md: OpenTofu `check` blocks (>= 1.9).

# RTX 4000 Ada plans (g2-gpu-*) are only offered in a subset of Linode regions
# (notably not London). Point-in-time list — re-check with:
#   linode-cli regions list-avail --json --all-rows
locals {
  rtx4000_ada_regions = ["de-fra-2", "fr-par", "us-ord", "us-sea", "jp-osa", "sg-sin-2", "in-bom-2"]
}

check "gpu_plan_available_in_region" {
  assert {
    condition     = !startswith(var.gpu_node_type, "g2-gpu") || contains(local.rtx4000_ada_regions, var.region)
    error_message = "gpu_node_type '${var.gpu_node_type}' (RTX 4000 Ada) is not known to be available in region '${var.region}'. Known regions: ${join(", ", local.rtx4000_ada_regions)}. Verify with `linode-cli regions list-avail`."
  }
}

check "public_gateway_with_open_api" {
  assert {
    condition     = var.gateway_service_type != "LoadBalancer"
    error_message = "gateway_service_type = LoadBalancer exposes the model endpoint on a public NodeBalancer with no authentication. Anyone who finds the IP can use the GPU."
  }
}
