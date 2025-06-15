output "cluster_endpoint" {
  value       = "https://${local.primary_control_node_ip}:6443"
  description = "Kubernetes API URL"
}

output "talosconfig_path" {
  value       = abspath(local_file.talosconfig.filename)
  description = "Path to talosconfig file"
}

output "kubeconfig_path" {
  value       = abspath(local_file.kubeconfig.filename)
  description = "Path to kubeconfig file"
}

output "control_node_ips" {
  value       = var.control_node_ips
  description = "Static IPs of control plane"
}

output "worker_node_ips" {
  value       = var.worker_node_ips
  description = "Static IPs of worker nodes"
}

output "cluster_status" {
  value       = "Cluster deployed at ${timestamp()}"
  description = "Status of the cluster deployment"
}
