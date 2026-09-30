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

# ─── GPU model servers ────────────────────────────────────────────────────────
# Ollama, vLLM and llama.cpp each claim the whole card. With one GPU node,
# two of them enabled means one pod stays Pending forever.
locals {
  gpu_model_servers_enabled = length([for enabled in [var.install_ollama, var.install_vllm, var.install_llamacpp] : enabled if enabled])
}

check "one_gpu_model_server" {
  assert {
    condition     = local.gpu_model_servers_enabled <= 1
    error_message = "More than one GPU model server is enabled (install_ollama, install_vllm, install_llamacpp). Each takes the whole GPU, so only one can run: disable the others, apply, then enable the one you want."
  }
}

check "vllm_requires_gpu_operator" {
  assert {
    condition     = !var.install_vllm || var.install_gpu_operator
    error_message = "install_vllm is enabled without install_gpu_operator. vLLM needs a GPU resource from a device plugin (the operator's, or HAMi's which depends on the operator)."
  }
}

check "vllm_with_hami_verify_full_vram" {
  assert {
    condition     = !(var.install_vllm && var.install_hami)
    error_message = "install_vllm with install_hami: the vLLM pod asks HAMi for 100% of the GPU's memory and cores. After it starts, check that the full ~20 GB is visible: make -C examples/vllm-opencode vram (nvidia-smi) and the 'KV cache' line in make -C examples/vllm-opencode logs. If not, set install_hami = false."
  }
}

check "vllm_gpu_plan_has_20gb" {
  assert {
    condition     = !var.install_vllm || local.gpu_vram_mib == null || local.gpu_vram_mib >= 20000
    error_message = "gpu_node_type '${var.gpu_node_type}' has less than 20 GB of VRAM per GPU. The vLLM presets are sized for 20 GB (weights 13.8 to 16.8 GB plus KV cache)."
  }
}

check "vllm_cache_retain_class" {
  assert {
    condition     = !var.install_vllm || var.vllm_cache_storage_class != "linode-block-storage-retain"
    error_message = "vllm_cache_storage_class = 'linode-block-storage-retain': the model cache volume survives tofu destroy and keeps being billed. Delete it in Cloud Manager when you no longer need it."
  }
}
