terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.8.1"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.111.200:8006/"
  username = "root@pam"
  password = var.proxmox_root_password
  insecure = true
}

provider "talos" {}