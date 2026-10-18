# Proxmox VMs that back the Talos nodes.
module "nodes" {
  source = "git::https://github.com/keller-IO/terraform-module.git//talos-proxmox-nodes?ref=2fa78d5aedfb34e54b7d2e5d7033c635d780687d"

  nodes = var.nodes

  # Talos is installed on scsi0. Detaching the installer prevents VM autostart
  # from depending on the shared CephFS ISO datastore.
  attach_install_iso = false

  talos_version      = var.talos_version
  talos_schematic_id = var.talos_schematic_id
  image_platform     = var.image_platform
  image_arch         = var.image_arch

  vm_storage_id  = var.vm_storage_id
  iso_storage_id = var.iso_storage_id

  default_cpu_cores        = var.default_cpu_cores
  default_cpu_sockets      = var.default_cpu_sockets
  default_cpu_type         = var.default_cpu_type
  default_memory_mb        = var.default_memory_mb
  default_disk_gb          = var.default_disk_gb
  default_longhorn_disk_gb = var.default_longhorn_disk_gb

  network_gateway = var.network_gateway
  network_subnet  = var.network_subnet
}

# Platform-agnostic Talos cluster configuration applied to those VMs.
module "cluster" {
  source = "git::https://github.com/keller-IO/terraform-module.git//talos-cluster?ref=2fa78d5aedfb34e54b7d2e5d7033c635d780687d"

  cluster_name        = var.cluster_name
  cluster_endpoint_ip = var.cluster_endpoint_ip

  talos_version      = var.talos_version
  talos_schematic_id = var.talos_schematic_id
  image_platform     = var.image_platform

  network_gateway      = var.network_gateway
  network_subnet       = var.network_subnet
  kubelet_valid_subnet = var.kubelet_valid_subnet

  nodes                             = module.nodes.talos_nodes
  extra_config_patches              = var.extra_config_patches
  extra_controlplane_config_patches = var.extra_controlplane_config_patches

  # Configure Talos only after the VMs exist and are reachable.
  depends_on = [module.nodes]
}
