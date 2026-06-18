# ---------------------------------------------------------------------------
# Proxmox / secrets
# ---------------------------------------------------------------------------
variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
  default   = null
}

variable "sops_age_private_key" {
  description = "Age private key mounted into the Argo CD repo-server so ksops can decrypt SOPS-encrypted manifests in the GitOps repo. Its public counterpart must be a recipient in the repo's .sops.yaml."
  type        = string
  sensitive   = true
  default     = null
}

# ---------------------------------------------------------------------------
# Git (Forgejo) / Argo CD
# ---------------------------------------------------------------------------
variable "git_token" {
  description = "Forgejo token/password with read access to the GitOps repo (used by Argo CD to clone it)."
  type        = string
  sensitive   = true
  default     = null
}

variable "git_username" {
  description = "Username for the Forgejo GitOps repo."
  type        = string
  default     = "kreativmonkey"
}

variable "argocd_repo_url" {
  description = "Git URL of the GitOps repo Argo CD reconciles."
  type        = string
  default     = "https://github.com/keller-IO/kubernetes-gitops.git"
}

variable "argocd_bootstrap_path" {
  description = "Path inside the GitOps repo that holds the root app-of-apps Argo CD reconciles."
  type        = string
  default     = "bootstrap"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (https://github.com/argoproj/argo-helm)."
  type        = string
  # renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
  default = "9.5.21"
}

variable "ksops_image" {
  description = "Image used by the repo-server init container to install KSOPS + kustomize."
  type        = string
  # renovate: datasource=docker depName=viaductoss/ksops
  default = "viaductoss/ksops:v4.5.1"
}

# ---------------------------------------------------------------------------
# Cluster (forwarded to the talos-cluster module)
# ---------------------------------------------------------------------------
variable "cluster_name" {
  type = string
}

variable "cluster_endpoint_ip" {
  type        = string
  description = "Control-plane VIP / Kubernetes API endpoint."
}

variable "talos_version" {
  type = string
  # renovate: datasource=github-releases depName=siderolabs/talos versioning=semver
  default = "v1.13.4"
}

variable "talos_schematic_id" {
  type = string
}

variable "image_platform" {
  type    = string
  default = "nocloud"
}

variable "image_arch" {
  type    = string
  default = "amd64"
}

variable "vm_storage_id" {
  type    = string
  default = "local-lvm"
}

variable "iso_storage_id" {
  type    = string
  default = "NFS-Storage"
}

# Worker defaults — applied to any node that does not override them. Control-plane
# nodes set explicit (smaller) resources in cluster.auto.tfvars.
variable "default_cpu_cores" {
  type    = number
  default = 4
}

variable "default_cpu_sockets" {
  type    = number
  default = 1
}

variable "default_cpu_type" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "default_memory_mb" {
  type    = number
  default = 16384
}

variable "default_disk_gb" {
  type    = number
  default = 40
}

# kellerIO uses an external Ceph cluster (via ceph-csi), not Longhorn, so nodes
# get no dedicated data disk by default. Set a node's longhorn_disk_gb to add one.
variable "default_longhorn_disk_gb" {
  type    = number
  default = 0
}

variable "network_gateway" {
  type    = string
  default = "192.168.2.1"
}

variable "network_subnet" {
  type    = number
  default = 24
}

variable "kubelet_valid_subnet" {
  description = "CIDR the kubelet must register a node IP from. Must match the node LAN so metrics-server/exec/port-forward work."
  type        = string
  default     = "192.168.2.0/24"
}

variable "nodes" {
  description = "Flat list of Talos nodes (see talos-cluster module for the schema and role semantics)."
  type = list(object({
    name             = string
    target_pve       = string
    ip_address       = string
    role             = optional(string, "controlplane")
    allow_scheduling = optional(bool)
    cpu_cores        = optional(number)
    cpu_sockets      = optional(number)
    cpu_type         = optional(string)
    memory_mb        = optional(number)
    disk_gb          = optional(number)
    longhorn_disk_gb = optional(number)
    extra_disks = optional(list(object({
      size         = number
      datastore_id = optional(string)
      interface    = optional(string)
    })), [])
  }))
}

variable "extra_config_patches" {
  description = "Additional Talos config patches applied to every node."
  type        = list(any)
  default     = []
}
