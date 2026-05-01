# Determine cluster name prefix: use provided value or fall back to system username.
locals {
  cluster_prefix = var.cluster_name_prefix != "" ? var.cluster_name_prefix : replace(lower(data.external.username.result.username), "/[^a-z0-9-]/", "-")
}

# Get system username when cluster_name_prefix is not set.
data "external" "username" {
  program = ["sh", "-c", "echo '{\"username\":\"'$(whoami)'\"}'"]
}
