# State migration from the module layout (before the "simplify" refactor) to the
# flat root layout. Each block maps a resource's old address onto its new one,
# so `tofu plan` shows moves instead of destroy-and-recreate, and no Helm
# release, namespace or model is touched. Safe to delete once every state has
# been applied with this file.

moved {
  from = module.metrics_server[0].helm_release.metrics_server
  to   = helm_release.metrics_server
}

moved {
  from = module.kube_prometheus_stack[0].kubernetes_namespace_v1.monitoring
  to   = kubernetes_namespace_v1.monitoring
}

moved {
  from = module.kube_prometheus_stack[0].helm_release.kube_prometheus_stack
  to   = helm_release.kube_prometheus_stack
}

moved {
  from = module.cert_manager[0].kubernetes_namespace_v1.cert_manager
  to   = kubernetes_namespace_v1.cert_manager
}

moved {
  from = module.cert_manager[0].helm_release.cert_manager
  to   = helm_release.cert_manager
}

moved {
  from = module.envoy_gateway[0].kubernetes_namespace_v1.envoy_gateway
  to   = kubernetes_namespace_v1.envoy_gateway
}

moved {
  from = module.envoy_gateway[0].helm_release.envoy_gateway
  to   = helm_release.envoy_gateway
}

moved {
  from = module.envoy_gateway[0].helm_release.gateway_class
  to   = helm_release.gateway_class
}

moved {
  from = module.kserve[0].kubernetes_namespace_v1.kserve
  to   = kubernetes_namespace_v1.kserve
}

moved {
  from = module.kserve[0].helm_release.kserve_crd
  to   = helm_release.kserve_crd
}

moved {
  from = module.kserve[0].helm_release.kserve
  to   = helm_release.kserve
}

moved {
  from = module.argo_cd[0].kubernetes_namespace_v1.argo_cd
  to   = kubernetes_namespace_v1.argo_cd
}

moved {
  from = module.argo_cd[0].helm_release.argo_cd
  to   = helm_release.argo_cd
}

# The bootstrap Application release was count-gated; it is now unconditional.
moved {
  from = module.argo_cd[0].helm_release.applications[0]
  to   = helm_release.applications
}
