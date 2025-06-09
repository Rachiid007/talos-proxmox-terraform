locals {
  control_macs = {
    for name, _ in var.control_nodes :
    name => format("DE:AD:BE:EF:0A:%02X", index(keys(var.control_nodes), name))
  }
  worker_macs = {
    for name, _ in var.worker_nodes :
    name => format("DE:AD:BE:EF:14:%02X", index(keys(var.worker_nodes), name))
  }

  primary_control_node_name = sort(keys(var.control_nodes))[0]
  primary_control_node_ip   = var.control_node_ips[local.primary_control_node_name]

  control_node_ips_list = values(var.control_node_ips)
  worker_node_ips_list  = values(var.worker_node_ips)
  node_ips_list         = concat(local.control_node_ips_list, local.worker_node_ips_list)
}

# 3. ISO download
resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type        = "iso"
  datastore_id        = var.proxmox_iso_datastore
  node_name           = values(var.control_nodes)[0] # any Proxmox host
  url                 = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/nocloud-amd64.iso"
  file_name           = "talos_linux-${var.talos_schematic_id}-${var.talos_version}-nocloud-amd64.iso"
  overwrite           = false
  overwrite_unmanaged = true
}

# shared blocks to avoid repetition
locals {
  common_vm_settings = {
    bios           = "ovmf"
    machine        = "q35"
    scsi_hardware  = "virtio-scsi-single"
    on_boot        = true
    started        = true
    operating_type = "l26"
  }
}

# control plane VMs
resource "proxmox_virtual_environment_vm" "talos_control_vm" {
  for_each = var.control_nodes

  name      = each.key
  node_name = each.value
  vm_id     = 110 + index(keys(var.control_nodes), each.key)
  tags      = ["talos", "control"]

  agent { enabled = true }

  bios          = local.common_vm_settings.bios
  machine       = local.common_vm_settings.machine
  scsi_hardware = local.common_vm_settings.scsi_hardware

  cpu {
    cores = var.proxmox_control_vm_cores
    type  = var.proxmox_vm_type
  }
  memory { dedicated = var.proxmox_control_vm_memory }
  disk {
    datastore_id = var.proxmox_image_datastore
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.proxmox_control_vm_disk_size
    file_format  = "raw"
    ssd          = true
  }
  efi_disk {
    datastore_id = var.proxmox_image_datastore
    type         = "4m"
    file_format  = "raw"
  }
  cdrom {
    interface = "scsi1"
    file_id   = proxmox_virtual_environment_download_file.talos_image.id
  }
  network_device {
    model       = "virtio"
    bridge      = "vmbr0"
    mac_address = local.control_macs[each.key]
  }
  operating_system { type = local.common_vm_settings.operating_type }

  lifecycle {
    ignore_changes = [network_device]
  }
}

# worker VMs
resource "proxmox_virtual_environment_vm" "talos_worker_vm" {
  for_each = var.worker_nodes

  name      = each.key
  node_name = each.value
  vm_id     = 120 + index(keys(var.worker_nodes), each.key)
  tags      = ["talos", "worker"]

  agent { enabled = true }

  bios          = local.common_vm_settings.bios
  machine       = local.common_vm_settings.machine
  scsi_hardware = local.common_vm_settings.scsi_hardware

  cpu {
    cores = var.proxmox_worker_vm_cores
    type  = var.proxmox_vm_type
  }
  memory { dedicated = var.proxmox_worker_vm_memory }
  disk {
    datastore_id = var.proxmox_image_datastore
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.proxmox_worker_vm_disk_size
    file_format  = "raw"
    ssd          = true
  }
  efi_disk {
    datastore_id = var.proxmox_image_datastore
    type         = "4m"
    file_format  = "raw"
  }
  cdrom {
    interface = "scsi1"
    file_id   = proxmox_virtual_environment_download_file.talos_image.id
  }
  network_device {
    model       = "virtio"
    bridge      = "vmbr0"
    mac_address = local.worker_macs[each.key]
  }
  operating_system { type = local.common_vm_settings.operating_type }

  lifecycle {
    ignore_changes = [network_device]
  }
}

# 5. Talos configuration & bootstrap

# Secrets for this cluster
resource "talos_machine_secrets" "secrets" {}

# Machine configs
data "talos_machine_configuration" "control" {
  cluster_name     = var.talos_cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${local.primary_control_node_ip}:6443"
  machine_secrets  = talos_machine_secrets.secrets.machine_secrets
  talos_version    = var.talos_version
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.talos_cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${local.primary_control_node_ip}:6443"
  machine_secrets  = talos_machine_secrets.secrets.machine_secrets
  talos_version    = var.talos_version
}

# Apply configs using **static IPs** (no guest‑agent race)
resource "talos_machine_configuration_apply" "control" {
  for_each                    = var.control_nodes
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control.machine_configuration
  node                        = var.control_node_ips[each.key]
  config_patches              = var.control_machine_config_patches
  apply_mode                  = "reboot"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = var.worker_nodes
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = var.worker_node_ips[each.key]
  config_patches              = var.worker_machine_config_patches
  apply_mode                  = "reboot"
}

# 120-second grace period for install/reboot
resource "time_sleep" "install_pause" {
  create_duration = "120s"
  depends_on      = [talos_machine_configuration_apply.control, talos_machine_configuration_apply.worker]
}

# One‑time bootstrap (first control node)
resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [time_sleep.install_pause]

  node                 = local.primary_control_node_ip
  client_configuration = talos_machine_secrets.secrets.client_configuration
}

# Fetch kubeconfig
resource "talos_cluster_kubeconfig" "cluster" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = local.primary_control_node_ip
}

data "talos_client_configuration" "client" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.secrets.client_configuration
  endpoints            = [local.primary_control_node_ip]
  nodes                = local.node_ips_list
}

# talosconfig file written to working dir
resource "local_file" "talosconfig" {
  filename = "${path.module}/talosconfig"
  content  = data.talos_client_configuration.client.talos_config
}

# kubeconfig
resource "local_file" "kubeconfig" {
  depends_on = [talos_cluster_kubeconfig.cluster]
  filename   = "${path.module}/kubeconfig"
  content    = talos_cluster_kubeconfig.cluster.kubeconfig_raw
}