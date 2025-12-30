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

# Create monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "kube-prometheus-stack"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Kube Prometheus Stack - comprehensive monitoring solution
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  create_namespace = false
  depends_on       = [kubernetes_namespace.monitoring]

  wait          = true
  timeout       = 900
  wait_for_jobs = true

  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          retention = var.prometheus_retention
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "linode-block-storage-retain"
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
          # Allow selecting all service monitors
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          # GPU monitoring integration (if enabled)
          additionalScrapeConfigs = var.enable_gpu_monitoring ? [
            {
              job_name = "dcgm-exporter"
              kubernetes_sd_configs = [
                {
                  role = "endpoints"
                  namespaces = {
                    names = ["gpu-operator"]
                  }
                }
              ]
            }
          ] : []
        }
      }
      # Grafana configuration
      grafana = {
        enabled       = true
        adminPassword = var.grafana_admin_password
        persistence = {
          enabled          = true
          size             = var.grafana_storage_size
          storageClassName = "linode-block-storage-retain"
        }
      }
      # Alertmanager configuration
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "linode-block-storage-retain"
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
      # Node exporter
      nodeExporter = {
        enabled = true
      }
      # Kube state metrics
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]
}
