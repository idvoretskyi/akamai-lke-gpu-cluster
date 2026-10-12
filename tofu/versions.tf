terraform {
  required_version = ">= 1.9"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    # Unused by this configuration. States created before the KServe rebuild
    # still hold module.hami[0].local_sensitive_file.kubeconfig, and OpenTofu
    # needs this provider's schema to refresh and drop that orphan; without it
    # plan/apply fail with "Failed to load plugin schemas". Remove once no such
    # states remain.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
