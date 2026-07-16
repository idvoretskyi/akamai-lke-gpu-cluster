# Token resolution order: LINODE_TOKEN environment variable, else the
# default user's token from ~/.config/linode-cli (see
# data.external.linode_token in locals.tf and scripts/get-linode-token.sh).
provider "linode" {
  token = local.linode_token
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
