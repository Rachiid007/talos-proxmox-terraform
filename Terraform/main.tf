# # Secrets for this cluster
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Apply the machine configuration created in the data section for the controller node
resource "talos_machine_configuration_apply" "controller_config_apply" {
  for_each = proxmox_virtual_environment_vm.talos_control_vm

  client_configuration        = data.talos_client_configuration.talosconfig.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_controller.machine_configuration
  node                        = var.control_node_ips[each.key]
  endpoint                    = var.control_node_ips[each.key]
  config_patches              = []
}

# Apply the machine configuration created in the data section for the worker node
resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each = proxmox_virtual_environment_vm.talos_worker_vm

  client_configuration        = data.talos_client_configuration.talosconfig.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  node                        = var.worker_node_ips[each.key]
  endpoint                    = var.worker_node_ips[each.key]
  config_patches              = []
  depends_on = [
    talos_machine_bootstrap.bootstrap,
    talos_machine_configuration_apply.controller_config_apply,
    data.talos_cluster_health.control_plane_health
  ]
}

# Start the bootstraping of the cluster
resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.controller_config_apply]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.primary_control_node_ip
}

# Collect the kubeconfig of the Talos cluster created
resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [
    talos_machine_bootstrap.bootstrap,
    data.talos_cluster_health.control_plane_health
  ]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.primary_control_node_ip
}

# talosconfig file written to working dir
resource "local_file" "talosconfig" {
  filename = "${path.module}/talosconfig"
  content  = data.talos_client_configuration.talosconfig.talos_config
}

# kubeconfig
resource "local_file" "kubeconfig" {
  depends_on = [talos_cluster_kubeconfig.kubeconfig]
  filename   = "${path.module}/kubeconfig"
  content    = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
}