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

# Everything below is an opinionated default rather than a variable: change it
# here if you really need to. Variables are kept for the things people vary.

locals {
  tags                    = ["lke", "gpu", "ml", "ai"]
  ha_control_plane        = false # +~$60/month
  system_node_count       = 1
  node_cidrs              = ["192.168.128.0/17"] # LKE private node range
  pod_cidrs               = ["10.2.0.0/16"]      # LKE pod range
  helm_timeout            = 600
  namespace_labels        = { "app.kubernetes.io/managed-by" = "opentofu" }
  model_namespace         = "vllm" # created by Argo CD; must not be "kserve"
  gitops_path             = "gitops/vllm"
  inference_service       = "qwen3"
  prometheus_retention    = "7d"
  prometheus_storage_size = "15Gi" # ~$1.50/month
  grafana_storage_size    = "5Gi"  # ~$0.50/month

  # Chart versions. Dependabot doesn't track these (Helm charts are not a
  # package ecosystem it understands here), so bump them by hand.
  chart_versions = {
    gpu_operator          = "v26.7.1"
    metrics_server        = "3.12.2"
    kube_prometheus_stack = "80.8.0"
    cert_manager          = "v1.21.2"
    envoy_gateway         = "v1.9.2"
    kserve                = "v0.20.0" # v0.21.0 charts are only on GHCR as -rc1
    argo_cd               = "10.10.1"
  }
}

# Node-pool scheduling primitives.
#
# Both pools carry `nodepool.lke/role`, so workloads pin to a pool with a
# nodeSelector (the values/*.yaml files pin the platform to "system"). The GPU
# pool is also tainted, so only GPU workloads (and the GPU Operator's operands,
# which tolerate it) land there; a model server needs the same toleration, a
# `nodepool.lke/role: gpu` selector and an `nvidia.com/gpu` limit.
locals {
  node_role_label_key = "nodepool.lke/role"
  system_node_labels  = { (local.node_role_label_key) = "system" }
  gpu_node_labels     = { (local.node_role_label_key) = "gpu" }

  gpu_node_taint = {
    key    = "nvidia.com/gpu"
    value  = "present"
    effect = "NoSchedule"
  }

  # CIDRs allowed to talk to each other inside the cluster (nodes + pods).
  intra_cluster_cidrs = concat(local.node_cidrs, local.pod_cidrs)

  # Pools are matched by instance type rather than list index, since the order
  # of the pool blocks is not guaranteed to be stable in state. This relies on
  # the system_node_type != gpu_node_type validation in variables.tf.
  gpu_pool    = one([for p in linode_lke_cluster.gpu_cluster.pool : p if p.type == var.gpu_node_type])
  system_pool = one([for p in linode_lke_cluster.gpu_cluster.pool : p if p.type == var.system_node_type])
}

# Decode the kubeconfig once; reused by the kubernetes and helm providers.
locals {
  kubeconfig = yamldecode(base64decode(linode_lke_cluster.gpu_cluster.kubeconfig))

  k8s_auth = {
    host                   = local.kubeconfig.clusters[0].cluster.server
    token                  = local.kubeconfig.users[0].user.token
    cluster_ca_certificate = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  }
}
