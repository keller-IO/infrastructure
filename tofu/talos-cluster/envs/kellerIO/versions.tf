terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
    # 18.10.2026: bewusst auf 0.11.x festgenagelt. Das Modul `talos-cluster`
    # (keller-IO-Ref b69b569, Basis v0.1.1) setzt in `talos_machine_configuration` weder `talos_version` noch
    # `kubernetes_version`; beides faellt dann auf die Defaults des Providers
    # zurueck. Provider 0.12 bringt Talos-Machinery 1.14 mit und wuerde damit
    # still den Config-Contract auf v1.14 und die Kubelet-/Control-Plane-Images
    # auf Kubernetes 1.37 heben. Unter dem 1.14-Contract sind unsere Legacy-
    # Patches (cluster.network/proxy, machine.network.nameservers,
    # machine.kubelet) ungueltig, und Talos wuerde zusaetzlich Flannel und
    # kube-proxy neben Cilium ausrollen. Den Pin erst zusammen mit dem Umstieg
    # auf `talos-cluster` v0.5.0 loesen (siehe docs/runbooks/day2-operations.md §4).
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
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
