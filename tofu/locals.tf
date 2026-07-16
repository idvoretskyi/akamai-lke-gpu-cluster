# Determine cluster name prefix: use provided value or fall back to system username.
locals {
  cluster_prefix = var.cluster_name_prefix != "" ? var.cluster_name_prefix : replace(lower(data.external.username.result.username), "/[^a-z0-9-]/", "-")
}

# Get system username when cluster_name_prefix is not set.
data "external" "username" {
  program = ["sh", "-c", "echo '{\"username\":\"'$(whoami)'\"}'"]
}

# Resolve the Linode API token: LINODE_TOKEN env var if set, else the default
# user's token from ~/.config/linode-cli (see providers.tf and
# scripts/get-linode-token.sh). Sensitive — never logged or shown in plans.
data "external" "linode_token" {
  program = ["${path.module}/scripts/get-linode-token.sh"]
}

locals {
  # null when neither source has a token, so the linode provider falls back
  # to its own LINODE_TOKEN env lookup (e.g. `tofu validate` in CI, with no
  # credentials at all, keeps working instead of erroring on an empty token).
  linode_token = data.external.linode_token.result.token != "" ? sensitive(data.external.linode_token.result.token) : null
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
  gpu_node_labels    = { (local.node_role_label_key) = "gpu" }

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
