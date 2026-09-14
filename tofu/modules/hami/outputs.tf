output "namespace" {
  description = "Namespace where HAMi is installed"
  value       = kubernetes_namespace_v1.hami.metadata[0].name
}
