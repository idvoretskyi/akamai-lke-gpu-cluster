output "namespace" {
  description = "Namespace where GPU operator is installed"
  value       = kubernetes_namespace_v1.gpu_operator.metadata[0].name
}
