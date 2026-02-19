terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent    = true
    username = "root"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  started   = true

  agent { enabled = false }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory { dedicated = 8192 }

  disk {
    datastore_id = var.proxmox_storage_vm
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = 16
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  operating_system { type = "l26" }

  initialization {
    datastore_id = var.proxmox_storage_vm

    ip_config {
      ipv4 {
        address = var.vm_ip
        gateway = var.vm_gateway
      }
    }

    dns {
      servers = [var.vm_dns]
    }

    user_account {
      username = var.vm_username
      keys     = [trimspace(var.vm_ssh_public_key)]
    }
  }
}
