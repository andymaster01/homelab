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

data "terraform_remote_state" "images" {
  backend = "local"
  config = {
    path = "${path.module}/../images/terraform.tfstate"
  }
}

resource "proxmox_virtual_environment_file" "vendor_cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/files/vendor-cloud-init.yaml", {
      username = var.vm_username
    })
    file_name = "${var.vm_name}-vendor-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  started   = true

  agent { enabled = true }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory { dedicated = 8192 }

  disk {
    datastore_id = var.proxmox_storage_vm
    file_id      = data.terraform_remote_state.images.outputs.ubuntu_cloud_image_id
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
    datastore_id        = var.proxmox_storage_vm
    vendor_data_file_id = proxmox_virtual_environment_file.vendor_cloud_init.id

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
