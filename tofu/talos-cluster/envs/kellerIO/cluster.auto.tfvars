# Non-sensitive cluster configuration for the "kellerIO" cluster (safe to commit).
# Secrets: secrets.auto.tfvars (local) or secrets.enc.yaml (SOPS, see secrets.enc.yaml.example).

# Proxmox cluster API endpoint (any node of the kellerIO Proxmox cluster).
# TODO: set the real endpoint of one of the cloud6x hosts.
proxmox_endpoint = "https://cloud61:8006"

cluster_name        = "kellerio"
cluster_endpoint_ip = "192.168.2.80" # control-plane VIP (unused IP just below the node range)

# Worker defaults (workers inherit these; control planes override below).
# No Longhorn disk: kellerIO uses an external Ceph cluster via ceph-csi.
default_cpu_cores        = 4
default_cpu_sockets      = 1
default_memory_mb        = 8192
default_disk_gb          = 40
default_longhorn_disk_gb = 0

# TODO: set storage IDs that exist on the kellerIO Proxmox cluster.
# iso_storage_id must be SHARED storage reachable from every Proxmox host
# (the ISO is downloaded once and booted by VMs across all target hosts).
vm_storage_id  = "local-zfs"
iso_storage_id = "cephfs"

# Roles:
#   role = "controlplane" + allow_scheduling = false -> manager only (dedicated)
#   role = "worker"                                   -> dedicated worker (uses defaults)
# Control planes are manager-only (allow_scheduling = false). Storage for workloads
# comes from the external Ceph cluster, so no node carries a local data disk.
# IPs start at 192.168.2.81; VMs are spread across cloud58/59/65/67/61/62.
nodes = [
  # --- Control plane (manager-only, smaller footprint) ---
  {
    name             = "kellerio-cp1"
    target_pve       = "cloud62"
    ip_address       = "192.168.2.81"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 2048
    disk_gb          = 20
  },
  {
    name             = "kellerio-cp2"
    target_pve       = "cloud61"
    ip_address       = "192.168.2.82"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 2048
    disk_gb          = 20
  },
  {
    name             = "kellerio-cp3"
    target_pve       = "cloud65"
    ip_address       = "192.168.2.83"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 2048
    disk_gb          = 20
  },

  # --- Workers (use the default_* resources) ---
  {
    name       = "kellerio-wrk1"
    target_pve = "cloud67"
    ip_address = "192.168.2.84"
    role       = "worker"
  },
  {
    name       = "kellerio-wrk2"
    target_pve = "cloud58"
    ip_address = "192.168.2.85"
    role       = "worker"
  },
  {
    name       = "kellerio-wrk3"
    target_pve = "cloud59"
    ip_address = "192.168.2.86"
    role       = "worker"
  },
]

# Talos image (guest_agent nfs_tools) — same schematic as homelab-kube.
talos_schematic_id = "3abf06e1d81e509d779dc256f9feae6cd6d82c69337c661cbfc383a92594faf5"
# renovate: datasource=github-releases depName=siderolabs/talos versioning=semver
talos_version  = "v1.13.4"
image_platform = "nocloud"
image_arch     = "amd64"

network_gateway      = "192.168.2.94"
network_subnet       = 24
kubelet_valid_subnet = "192.168.2.0/24"

# GitOps: Argo CD reconciles the keller.io repo (root app-of-apps under bootstrap/).
argocd_repo_url       = "https://github.com/keller-IO/kubernetes-gitops.git"
argocd_bootstrap_path = "clusters/main"
git_username          = "ltsavar"
