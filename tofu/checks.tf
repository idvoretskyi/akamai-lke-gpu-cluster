# Advisory (non-blocking) checks — warnings only, never fail `tofu apply`.
# See AGENTS.md: OpenTofu `check` blocks (>= 1.9).
#
# Note: install_hami requiring install_gpu_operator is a hard error (variable
# validation on install_hami in variables.tf), not just advisory here — HAMi
# is entirely non-functional without the operator's driver/toolkit, so it's
# treated as a real misconfiguration rather than a "you might want to
# reconsider" suggestion.

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
# sanity-check how much GPU memory Ollama and vLLM ask HAMi for.
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

check "vllm_requires_gpu_operator" {
  assert {
    condition     = !var.install_vllm || var.install_gpu_operator
    error_message = "install_vllm is enabled without install_gpu_operator — vLLM needs the NVIDIA driver/toolkit to use the GPU and will not schedule without an nvidia.com/gpu resource."
  }
}

check "vllm_gpu_memory_fits_card" {
  assert {
    condition     = !var.install_vllm || !var.install_hami || local.gpu_vram_mib == null || var.vllm_gpu_memory_mib <= local.gpu_vram_mib
    error_message = "vllm_gpu_memory_mib (${var.vllm_gpu_memory_mib}) exceeds the ${coalesce(local.gpu_vram_mib, 0)} MiB of VRAM on one '${var.gpu_node_type}' GPU — HAMi will never schedule the vLLM pod."
  }
}

# Ollama and vLLM both default to the whole GPU. With a single GPU node, running
# both needs HAMi and their gpumem requests to fit one card together; otherwise
# whichever pod schedules second stays Pending. A second GPU node lets each
# engine take its own card.
check "llm_engines_share_one_gpu" {
  assert {
    condition = (
      !(var.install_ollama && var.install_vllm)
      || var.gpu_node_count >= 2
      || (var.install_hami && (local.gpu_vram_mib == null || var.ollama_gpu_memory_mib + var.vllm_gpu_memory_mib <= local.gpu_vram_mib))
    )
    error_message = "install_ollama and install_vllm are both enabled on a single GPU node, but ${var.install_hami ? "ollama_gpu_memory_mib + vllm_gpu_memory_mib (${var.ollama_gpu_memory_mib + var.vllm_gpu_memory_mib} MiB) exceeds the card's ${coalesce(local.gpu_vram_mib, 0)} MiB" : "install_hami = false, so each engine claims the whole GPU"} — one of the two pods will stay Pending. Disable one engine, or (with HAMi) lower the two gpu_memory_mib values so they fit together."
  }
}
