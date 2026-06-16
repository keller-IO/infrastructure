terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.24.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.15.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}
