# Provider will automatically use LINODE_TOKEN environment variable.
# Set via: export LINODE_TOKEN=$(linode-cli configure get token)
provider "linode" {
  # token is read from LINODE_TOKEN environment variable
}

# Kubernetes provider — uses kubeconfig from the LKE cluster resource.
# See local.k8s_auth in locals.tf for the shared kubeconfig data.
provider "kubernetes" {
  host                   = local.k8s_auth.host
  token                  = local.k8s_auth.token
  cluster_ca_certificate = local.k8s_auth.cluster_ca_certificate
}

# Helm provider — uses the same kubeconfig data as the kubernetes provider.
provider "helm" {
  kubernetes = {
    host                   = local.k8s_auth.host
    token                  = local.k8s_auth.token
    cluster_ca_certificate = local.k8s_auth.cluster_ca_certificate
  }
}
