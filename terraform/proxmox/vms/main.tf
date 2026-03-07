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
  for_each     = var.vms
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.node_name

  source_raw {
    data = templatefile("${path.module}/files/vendor-cloud-init.yaml", {
      username = each.value.username
    })
    file_name = "${each.key}-vendor-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each  = var.vms
  name      = each.key
  node_name = each.value.node_name
  vm_id     = each.value.vm_id
  started   = true

  agent { enabled = true }

  cpu {
    cores   = each.value.cpu_cores
    sockets = 1
    type    = "host"
  }

  memory { dedicated = each.value.memory }

  disk {
    datastore_id = each.value.storage
    file_id      = data.terraform_remote_state.images.outputs.ubuntu_cloud_image_ids[each.value.node_name]
    interface    = "virtio0"
    size         = each.value.disk_size
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge = each.value.bridge
    model  = "virtio"
  }

  operating_system { type = "l26" }

  initialization {
    datastore_id        = each.value.storage
    vendor_data_file_id = proxmox_virtual_environment_file.vendor_cloud_init[each.key].id

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gateway
      }
    }

    dns {
      servers = [each.value.dns]
    }

    user_account {
      username = each.value.username
      keys     = [trimspace(var.vm_ssh_public_key)]
    }
  }
}
