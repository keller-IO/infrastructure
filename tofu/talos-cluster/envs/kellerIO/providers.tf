provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = local.proxmox_api_token
  insecure  = true
}

provider "talos" {}

provider "kubernetes" {
  host                   = module.cluster.kubernetes_client_configuration.host
  client_certificate     = base64decode(module.cluster.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(module.cluster.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(module.cluster.kubernetes_client_configuration.ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = module.cluster.kubernetes_client_configuration.host
    client_certificate     = base64decode(module.cluster.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(module.cluster.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(module.cluster.kubernetes_client_configuration.ca_certificate)
  }
}
