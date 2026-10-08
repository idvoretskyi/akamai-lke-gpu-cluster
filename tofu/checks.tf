# Advisory (non-blocking) checks — warnings only, never fail `tofu apply`.
# See AGENTS.md: OpenTofu `check` blocks (>= 1.9).
#
# Note: install_hami requiring install_gpu_operator is a hard error (variable
# validation on install_hami in variables.tf), not just advisory here — HAMi
# is entirely non-functional without the operator's driver/toolkit, so it's
# treated as a real misconfiguration rather than a "you might want to
# reconsider" suggestion.

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

# Per-card VRAM (MiB) of Linode GPU plans, keyed by plan-name prefix. Used to
# sanity-check how much GPU memory Ollama asks HAMi for.
locals {
  gpu_vram_mib_by_plan_prefix = {
    "g2-gpu-rtx4000a" = 20475 # RTX 4000 Ada, 20 GB
    "g1-gpu-rtx6000"  = 24576 # Quadro RTX 6000, 24 GB
  }
  gpu_vram_mib = one([for prefix, mib in local.gpu_vram_mib_by_plan_prefix : mib if startswith(var.gpu_node_type, prefix)])
}

check "ollama_requires_gpu_operator" {
  assert {
    condition     = !var.install_ollama || var.install_gpu_operator
    error_message = "install_ollama is enabled without install_gpu_operator — Ollama needs the NVIDIA driver/toolkit to use the GPU and will not schedule without an nvidia.com/gpu resource."
  }
}

check "ollama_gpu_memory_fits_card" {
  assert {
    condition     = !var.install_ollama || !var.install_hami || local.gpu_vram_mib == null || var.ollama_gpu_memory_mib <= local.gpu_vram_mib
    error_message = "ollama_gpu_memory_mib (${var.ollama_gpu_memory_mib}) exceeds the ${coalesce(local.gpu_vram_mib, 0)} MiB of VRAM on one '${var.gpu_node_type}' GPU — HAMi will never schedule the Ollama pod."
  }
}

check "ollama_leaves_headroom_for_default_slice" {
  assert {
    condition     = !var.install_ollama || !var.install_hami || local.gpu_vram_mib == null || var.hami_default_gpu_memory == 0 || var.ollama_gpu_memory_mib + var.hami_default_gpu_memory <= local.gpu_vram_mib
    error_message = "ollama_gpu_memory_mib (${var.ollama_gpu_memory_mib}) + hami_default_gpu_memory (${var.hami_default_gpu_memory}) exceeds the ${coalesce(local.gpu_vram_mib, 0)} MiB of VRAM on one '${var.gpu_node_type}' GPU — a plain nvidia.com/gpu pod (e.g. an Argo Workflow GPU step) will not schedule while Ollama runs."
  }
}

check "open_webui_requires_ollama" {
  assert {
    condition     = !var.install_open_webui || var.install_ollama
    error_message = "install_open_webui is enabled without install_ollama — Open WebUI has no model backend to talk to."
  }
}

check "argo_workflows_gpu_steps_need_hami" {
  assert {
    condition     = !var.install_argo_workflows || !var.install_ollama || var.install_hami
    error_message = "install_argo_workflows and install_ollama are both enabled without install_hami — Ollama then holds the whole GPU and Argo Workflow GPU steps will not schedule."
  }
}
