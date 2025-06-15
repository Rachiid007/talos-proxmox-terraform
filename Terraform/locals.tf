locals {
  control_macs = {
    for name, _ in var.control_nodes :
    name => format("DE:AD:BE:EF:0A:%02X", index(keys(var.control_nodes), name))
  }
  worker_macs = {
    for name, _ in var.worker_nodes :
    name => format("DE:AD:BE:EF:14:%02X", index(keys(var.worker_nodes), name))
  }

  primary_control_node_name = sort(keys(var.control_node_ips))[0]
  primary_control_node_ip   = var.control_node_ips[local.primary_control_node_name]

  control_node_ips_list = values(var.control_node_ips)
  worker_node_ips_list  = values(var.worker_node_ips)
  node_ips_list         = concat(local.control_node_ips_list, local.worker_node_ips_list)
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type        = "iso"
  datastore_id        = var.proxmox_iso_datastore
  node_name           = values(var.control_nodes)[0]
  url                 = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/nocloud-amd64.iso"
  file_name           = "talos_linux-${var.talos_schematic_id}-${var.talos_version}-nocloud-amd64.iso"
  overwrite           = false
  overwrite_unmanaged = true
}

# shared blocks to avoid repetition
locals {
  common_vm_settings = {
    bios                  = "ovmf"
    machine               = "q35"
    scsi_hardware         = "virtio-scsi-single"
    on_boot               = true
    operating_system_type = "l26"
  }
}

# control plane VMs
resource "proxmox_virtual_environment_vm" "talos_control_vm" {
  for_each = var.control_nodes

  name      = each.key
  node_name = each.value
  vm_id     = 110 + index(keys(var.control_nodes), each.key)
  tags      = ["talos", "control"]
  on_boot   = local.common_vm_settings.on_boot

  agent {
    enabled = true
    # trim = true # better disk management
    # type = "virtio" # for explicitness
  }

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
    # Using static MAC addresses ensures Talos VMs consistently get their assigned IPs (reserved by my DHCP Server)
  }
  operating_system { type = local.common_vm_settings.operating_system_type }

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
  on_boot   = local.common_vm_settings.on_boot

  agent {
    enabled = true
    # trim = true # for better disk management
    # type = "virtio" # for explicitness
  }

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
    # Using static MAC addresses ensures Talos VMs consistently get their assigned IPs
  }

  operating_system { type = local.common_vm_settings.operating_system_type }

  lifecycle {
    ignore_changes = [network_device]
  }
}

# Generate the Talos client configuration
data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_node_ips_list
  nodes                = local.node_ips_list
}

# Generate the controller configuration and instantiate the Initial Image for the Talos configuration
data "talos_machine_configuration" "machineconfig_controller" {
  cluster_name     = var.talos_cluster_name
  talos_version    = var.talos_version
  cluster_endpoint = "https://${local.primary_control_node_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = length(var.control_machine_config_patches) > 0 ? var.control_machine_config_patches : [
    <<EOF
machine:
  install:
    disk: ${var.talos_install_disk}
EOF
  ]
}

# Generate the worker configuration and instantiate the Initial Image for the Talos configuration
data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.talos_cluster_name
  talos_version    = var.talos_version
  cluster_endpoint = "https://${local.primary_control_node_ip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = length(var.worker_machine_config_patches) > 0 ? var.worker_machine_config_patches : [
    <<EOF
machine:
  install:
    disk: ${var.talos_install_disk}
EOF
  ]
}

# Check whether the Talos control plane is in a healthy state
data "talos_cluster_health" "control_plane_health" {
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = local.control_node_ips_list
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
  depends_on           = [talos_machine_bootstrap.bootstrap]
}

# Check whether the Talos cluster is in a healthy state
data "talos_cluster_health" "cluster_health" {
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = local.control_node_ips_list
  worker_nodes         = local.worker_node_ips_list
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
}
