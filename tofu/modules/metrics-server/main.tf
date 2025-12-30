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

# Metrics Server - provides resource metrics API for kubectl top and HPA
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
      # Required for Linode LKE compatibility
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP"
      ]
      # Resource limits for production workloads
      resources = {
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "400Mi"
        }
      }
      # High availability configuration
      replicas = 2
      podDisruptionBudget = {
        enabled      = true
        minAvailable = 1
      }
    })
  ]
}
