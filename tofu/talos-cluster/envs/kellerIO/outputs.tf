resource "local_file" "talosconfig" {
  content         = module.cluster.talosconfig
  filename        = "${path.module}/talosconfig"
  file_permission = "0600"
}

resource "local_file" "kubeconfig" {
  content         = module.cluster.kubeconfig
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

output "control_plane_nodes" {
  description = "Control-plane node names."
  value       = keys(module.cluster.control_plane_nodes)
}

output "worker_nodes" {
  description = "Worker node names."
  value       = keys(module.cluster.worker_nodes)
}
