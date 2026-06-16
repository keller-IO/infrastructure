# Non-sensitive cluster configuration for the "kellerIO" cluster (safe to commit).
# Secrets: secrets.auto.tfvars (local) or secrets.enc.yaml (SOPS, see secrets.enc.yaml.example).

# Proxmox cluster API endpoint (any node of the kellerIO Proxmox cluster).
# TODO: set the real endpoint of one of the cloud6x hosts.
proxmox_endpoint = "https://cloud61:8006"

cluster_name        = "kellerio"
cluster_endpoint_ip = "192.168.2.69" # control-plane VIP (unused IP just below the node range)

# Worker defaults (workers inherit these; control planes override below).
# No Longhorn disk: kellerIO uses an external Ceph cluster via ceph-csi.
default_cpu_cores        = 4
default_cpu_sockets      = 1
default_memory_mb        = 16384
default_disk_gb          = 40
default_longhorn_disk_gb = 0

# TODO: set storage IDs that exist on the kellerIO Proxmox cluster.
# iso_storage_id must be SHARED storage reachable from every cloud6x host
# (the ISO is downloaded once and booted by VMs on all four hosts).
vm_storage_id  = "local-lvm"
iso_storage_id = "NFS-Storage"

# Roles:
#   role = "controlplane" + allow_scheduling = false -> manager only (dedicated)
#   role = "worker"                                   -> dedicated worker (uses defaults)
# Control planes are manager-only (allow_scheduling = false). Storage for workloads
# comes from the external Ceph cluster, so no node carries a local data disk.
# IPs start at 192.168.2.70; VMs are spread across cloud64/65/62/61.
nodes = [
  # --- Control plane (manager-only, smaller footprint) ---
  {
    name             = "kellerio-cp1"
    target_pve       = "cloud64"
    ip_address       = "192.168.2.70"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 8192
    disk_gb          = 40
  },
  {
    name             = "kellerio-cp2"
    target_pve       = "cloud65"
    ip_address       = "192.168.2.71"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 8192
    disk_gb          = 40
  },
  {
    name             = "kellerio-cp3"
    target_pve       = "cloud62"
    ip_address       = "192.168.2.72"
    role             = "controlplane"
    allow_scheduling = false
    cpu_cores        = 2
    memory_mb        = 8192
    disk_gb          = 40
  },

  # --- Workers (use the default_* resources) ---
  {
    name       = "kellerio-wrk1"
    target_pve = "cloud61"
    ip_address = "192.168.2.73"
    role       = "worker"
  },
  {
    name       = "kellerio-wrk2"
    target_pve = "cloud64"
    ip_address = "192.168.2.74"
    role       = "worker"
  },
  {
    name       = "kellerio-wrk3"
    target_pve = "cloud65"
    ip_address = "192.168.2.75"
    role       = "worker"
  },
]

# Talos image (guest_agent, iscsi_tools, nfs_tools) — same schematic as homelab-kube.
talos_schematic_id = "10f9392d7091b30abf573524649756e5bc894f653af525836e9ab0297f301fc2"
# renovate: datasource=github-releases depName=siderolabs/talos versioning=semver
talos_version  = "v1.13.4"
image_platform = "nocloud"
image_arch     = "amd64"

network_gateway      = "192.168.2.1"
network_subnet       = 24
kubelet_valid_subnet = "192.168.2.0/24"

# GitOps: Argo CD reconciles the keller.io repo (root app-of-apps under bootstrap/).
argocd_repo_url       = "https://git.f4mily.net/kreativmonkey/keller.io.git"
argocd_bootstrap_path = "bootstrap"
git_username          = "kreativmonkey"
