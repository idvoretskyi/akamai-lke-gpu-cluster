# Determine cluster name prefix: use provided value or fall back to system username.
locals {
  cluster_prefix = var.cluster_name_prefix != "" ? var.cluster_name_prefix : replace(lower(data.external.username.result.username), "/[^a-z0-9-]/", "-")
}

# Get system username when cluster_name_prefix is not set.
data "external" "username" {
  program = ["sh", "-c", "echo '{\"username\":\"'$(whoami)'\"}'"]
}

# Resolve a Linode API token fallback from the default user in
# ~/.config/linode-cli (linode-cli's own config file), for machines that are
# already `linode-cli configure`'d and don't want a separate
# `export LINODE_TOKEN`. Implemented with plain HCL functions (file/regex),
# NOT a data source — data source results are persisted into OpenTofu state,
# and this repo doesn't want the token to end up there even though state is
# local/gitignored (see AGENTS.md). Locals are never written to state.
#
# Precedence note: because there's no built-in way to read an arbitrary
# environment variable from HCL (only TF_VAR_* via variables), this can't
# check whether LINODE_TOKEN is already set and prefer it — if the
# linode-cli config file resolves to a token, it takes priority here over
# LINODE_TOKEN. For this single-owner lab repo that's an acceptable
# trade-off; if you need to override with a different token, temporarily
# rename ~/.config/linode-cli or update its default user's token instead.
locals {
  linode_cli_config_path  = pathexpand("~/.config/linode-cli")
  linode_cli_config       = fileexists(local.linode_cli_config_path) ? file(local.linode_cli_config_path) : ""
  linode_cli_default_user = try(regex("(?m)^default-user\\s*=\\s*(\\S+)", local.linode_cli_config)[0], null)
  linode_cli_token = local.linode_cli_default_user == null ? null : try(
    regex("(?s)\\[${local.linode_cli_default_user}\\].*?\\ntoken\\s*=\\s*(\\S+)", local.linode_cli_config)[0],
    null
  )

  # null falls through to the linode provider's own LINODE_TOKEN env lookup
  # (e.g. `tofu validate`/`plan` in CI, with no linode-cli config at all,
  # keeps working instead of erroring on an empty token).
  linode_token = local.linode_cli_token != null ? sensitive(local.linode_cli_token) : null
}

# Node-pool scheduling primitives.
#
# Both pools are labelled with `nodepool.lke/role` so workloads can be pinned to
# the right pool via nodeSelector. The GPU pool is additionally tainted (when
# var.dedicate_gpu_nodes is true) so that only GPU workloads — and the GPU
# Operator's GPU operands, which tolerate this taint by default — land there.
locals {
  node_role_label_key = "nodepool.lke/role"

  system_node_labels = { (local.node_role_label_key) = "system" }
  # "gpu" = "on" matches the label the HAMi chart's devicePlugin targets by
  # default (devicePlugin.nvidiaNodeSelector); Helm merges map values rather
  # than replacing them, so the module's nvidia_node_selector override is
  # additive on top of that default — the GPU nodes must carry both labels.
  gpu_node_labels = { (local.node_role_label_key) = "gpu", gpu = "on" }

  # Selector used to pin system/monitoring workloads onto the system pool.
  system_node_selector = local.system_node_labels

  # The taint applied to GPU nodes. The NVIDIA GPU Operator tolerates a taint
  # with this key (nvidia.com/gpu) by default, so its operands keep scheduling
  # onto GPU nodes. User GPU workloads must add a matching toleration.
  gpu_node_taint = {
    key    = "nvidia.com/gpu"
    value  = "present"
    effect = "NoSchedule"
  }

  # Toleration handed to modules; null when GPU nodes are not dedicated.
  gpu_node_toleration = var.dedicate_gpu_nodes ? local.gpu_node_taint : null

  # CIDRs allowed to talk to each other inside the cluster (nodes + pods).
  intra_cluster_cidrs = concat(var.node_cidrs, var.pod_cidrs)

  # GPU monitoring only makes sense when the GPU Operator (DCGM) is installed.
  gpu_monitoring_enabled = var.enable_gpu_monitoring && var.install_gpu_operator

  # Pools are matched by instance type rather than list index, since the order
  # of the pool blocks is not guaranteed to be stable in state. This relies on
  # the system_node_type != gpu_node_type validation in variables.tf.
  gpu_pool    = one([for p in linode_lke_cluster.gpu_cluster.pool : p if p.type == var.gpu_node_type])
  system_pool = one([for p in linode_lke_cluster.gpu_cluster.pool : p if p.type == var.system_node_type])
}

# Decode and parse the kubeconfig once; reused by kubernetes and helm providers.
locals {
  kubeconfig = yamldecode(base64decode(linode_lke_cluster.gpu_cluster.kubeconfig))

  k8s_auth = {
    host                   = local.kubeconfig.clusters[0].cluster.server
    token                  = local.kubeconfig.users[0].user.token
    cluster_ca_certificate = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  }
}

# vLLM model presets, all sized for one 20 GB RTX 4000 Ada (0.92 of the
# card for vLLM). max_len_20gb is the longest context each one can serve
# there: measured from vLLM's KV cache report where noted, else computed from
# the model config (FP8 KV cache). Newer Qwen (3.5/3.6/3.8), GLM and Kimi
# models are 24 GB or more at 4-bit and do not fit.
locals {
  vllm_profiles = {
    # Qwen3-Coder-30B-A3B (July 2025): coding-tuned MoE, ~3B active, fast.
    # 16.8 GB of AWQ weights leave 1.15 GiB of KV cache: vLLM measured a
    # 25,024-token maximum, so 24K.
    "qwen3-coder-30b" = {
      model_repo        = "QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ"
      served_model_name = "qwen3-coder-30b"
      max_model_len     = 24576
      max_len_20gb      = 25024
      tool_call_parser  = "qwen3_coder"
      reasoning_parser  = null
      extra_args        = []
    }
    # gpt-oss-20b: MXFP4 MoE, 13.8 GB, 64K with room for 2.5 concurrent
    # requests (measured 167,018-token KV cache). vLLM v0.30.0 sometimes
    # leaks Harmony markers into tool names (vllm-project/vllm#32587);
    # opencode retries, but expect extra turns.
    "gpt-oss-20b" = {
      model_repo        = "openai/gpt-oss-20b"
      served_model_name = "gpt-oss-20b"
      max_model_len     = 65536
      max_len_20gb      = 131072
      tool_call_parser  = "openai"
      reasoning_parser  = "openai_gptoss"
      extra_args        = []
    }
    # Qwen3-14B (April 2025): official Qwen AWQ, dense, 10 GB. Slower than the
    # MoEs but fits its full native 40K context with room to spare.
    "qwen3-14b" = {
      model_repo        = "Qwen/Qwen3-14B-AWQ"
      served_model_name = "qwen3-14b"
      max_model_len     = 40960
      max_len_20gb      = 40960
      tool_call_parser  = "hermes"
      reasoning_parser  = "qwen3"
      extra_args        = []
    }
  }

  vllm_profile       = local.vllm_profiles[var.vllm_model_profile]
  vllm_max_model_len = coalesce(var.vllm_max_model_len, local.vllm_profile.max_model_len)
}
