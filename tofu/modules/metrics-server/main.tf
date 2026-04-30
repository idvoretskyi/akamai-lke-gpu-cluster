terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

# Metrics Server — provides the resource metrics API for kubectl top and HPA.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = var.namespace

  timeout = 300
  wait    = true

  values = [
    yamlencode({
      # Required args for Linode LKE compatibility
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP",
      ]
      resources = var.resources
      replicas  = var.replicas
      podDisruptionBudget = {
        enabled      = var.replicas > 1
        minAvailable = 1
      }
    })
  ]
}
