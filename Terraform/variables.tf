variable "proxmox_root_password" {
  type = string
}
variable "proxmox_iso_datastore" {
  type    = string
  default = "local"
}
variable "proxmox_image_datastore" {
  type    = string
  default = "local-lvm"
}
variable "proxmox_control_vm_cores" {
  type    = number
  default = 4
}
variable "proxmox_worker_vm_cores" {
  type    = number
  default = 4
}
variable "proxmox_control_vm_memory" {
  type    = number
  default = 8192
}
variable "proxmox_worker_vm_memory" {
  type    = number
  default = 4096
}

variable "proxmox_control_vm_disk_size" {
  type    = number
  default = 32
}
variable "proxmox_worker_vm_disk_size" {
  type    = number
  default = 50
}

variable "proxmox_vm_type" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "talos_cluster_name" {
  type    = string
  default = "my-talos-cluster"
}
variable "talos_version" {
  type    = string
  default = "1.10.3"
}
variable "talos_schematic_id" {
  type    = string
  default = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

# Node → Proxmox‑host maps
variable "control_nodes" { type = map(string) }
variable "worker_nodes" { type = map(string) }

# Static IPs (string maps)
variable "control_node_ips" { type = map(string) }
variable "worker_node_ips" { type = map(string) }

# General network extras
variable "network_gateway" {
  type    = string
  default = "192.168.111.1"
}
variable "dns_servers" {
  type    = list(string)
  default = ["192.168.111.1"]
}
variable "dns_domain" {
  type    = string
  default = "home.arpa"
}
variable "talos_install_disk" {
  type    = string
  default = "/dev/vda"
}

# Optional machine‑config patches
variable "control_machine_config_patches" {
  type = list(string)
  default = [<<EOF
machine:
  install:
    disk: "/dev/vda"
EOF
  ]
}

variable "worker_machine_config_patches" {
  type = list(string)
  default = [<<EOF
machine:
  install:
    disk: "/dev/vda"
EOF
  ]
}