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

# Create namespace for GPU operator
resource "kubernetes_namespace" "gpu_operator" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "gpu-operator"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Install NVIDIA GPU Operator via Helm
resource "helm_release" "gpu_operator" {
  name       = "gpu-operator"
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_version
  namespace  = kubernetes_namespace.gpu_operator.metadata[0].name

  create_namespace = false
  depends_on       = [kubernetes_namespace.gpu_operator]

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    yamlencode({
      # GPU Operator runtime configuration
      operator = {
        defaultRuntime = "containerd"
      }
      # NVIDIA driver installation
      driver = {
        enabled = var.install_driver
      }
      # NVIDIA Container Toolkit
      toolkit = {
        enabled = true
      }
      # GPU device plugin for Kubernetes
      devicePlugin = {
        enabled = true
      }
      # DCGM Exporter for GPU metrics in Prometheus
      dcgmExporter = {
        enabled = var.enable_dcgm_exporter
      }
      # GPU Feature Discovery
      gfd = {
        enabled = true
      }
      # MIG Manager (not needed for RTX 4000 Ada)
      migManager = {
        enabled = false
      }
      # Node Status Exporter
      nodeStatusExporter = {
        enabled = var.enable_node_status_exporter
      }
      # GPU validation with workload testing
      validator = {
        plugin = {
          env = [
            {
              name  = "WITH_WORKLOAD"
              value = "true"
            }
          ]
        }
      }
    })
  ]
}

# Wait for GPU operator to be fully ready
resource "terraform_data" "wait_for_gpu_operator" {
  depends_on = [helm_release.gpu_operator]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for GPU operator pods to be ready..."
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/component=gpu-operator \
        -n ${kubernetes_namespace.gpu_operator.metadata[0].name} \
        --timeout=600s || true

      echo "Waiting for nvidia-driver-daemonset..."
      kubectl wait --for=condition=ready pod \
        -l app=nvidia-driver-daemonset \
        -n ${kubernetes_namespace.gpu_operator.metadata[0].name} \
        --timeout=600s || true

      echo "GPU Operator installation complete!"
    EOT
  }
}
