# Decode and parse the kubeconfig once; reused by kubernetes and helm providers.
locals {
  kubeconfig = yamldecode(base64decode(linode_lke_cluster.gpu_cluster.kubeconfig))
}

# Provider will automatically use LINODE_TOKEN environment variable.
# Set via: export LINODE_TOKEN=$(linode-cli configure get token)
provider "linode" {
  # token is read from LINODE_TOKEN environment variable
}

# Kubernetes provider — uses kubeconfig from the LKE cluster resource.
provider "kubernetes" {
  host                   = local.kubeconfig.clusters[0].cluster.server
  token                  = local.kubeconfig.users[0].user.token
  cluster_ca_certificate = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
}

# Helm provider — uses the same kubeconfig data as the kubernetes provider.
provider "helm" {
  kubernetes = {
    host                   = local.kubeconfig.clusters[0].cluster.server
    token                  = local.kubeconfig.users[0].user.token
    cluster_ca_certificate = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  }
}
