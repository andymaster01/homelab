# Implementation Plan: Terraform Multi-Node & Multi-VM Refactoring

> **How this works:** This plan is divided into stages. The agent MUST ask for confirmation before starting each stage and MUST wait for explicit approval before advancing. Never auto-advance.

---

## Stage 1: Refactor Terraform Images Module for Multi-Node

**Goal:** Make the cloud image available on both Proxmox nodes (bahamut + eiko) by converting the images module to use `for_each` over a list of nodes.

### Files to modify

**`terraform/proxmox/terraform.tfvars`** — remove `proxmox_node`, keep only connection vars:
```hcl
proxmox_endpoint = "https://192.168.1.101:8006/"
proxmox_insecure = true
```

**`terraform/proxmox/images/variables.tf`** — replace single `proxmox_node` with a `proxmox_nodes` list:
```hcl
variable "proxmox_nodes" {
  description = "List of Proxmox node names to download images to"
  type        = list(string)
}
```
Keep `proxmox_endpoint`, `proxmox_api_token`, `proxmox_insecure`, `proxmox_storage_iso` unchanged.

**`terraform/proxmox/images/terraform.tfvars`** — add (create this file):
```hcl
proxmox_nodes = ["bahamut", "eiko"]
```

**`terraform/proxmox/images/main.tf`** — convert the download resource to `for_each`:
```hcl
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each     = toset(var.proxmox_nodes)
  content_type = "iso"
  datastore_id = var.proxmox_storage_iso
  node_name    = each.value
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-cloudimg-amd64.img"
}
```

**`terraform/proxmox/images/outputs.tf`** — output a map of image IDs keyed by node:
```hcl
output "ubuntu_cloud_image_ids" {
  description = "Map of node name to cloud image file ID"
  value       = { for node, img in proxmox_virtual_environment_download_file.ubuntu_cloud_image : node => img.id }
}
```

### State migration

The existing image resource address changes from `proxmox_virtual_environment_download_file.ubuntu_cloud_image` to `proxmox_virtual_environment_download_file.ubuntu_cloud_image["bahamut"]`. Run:
```bash
cd terraform/proxmox/images
terraform state mv \
  'proxmox_virtual_environment_download_file.ubuntu_cloud_image' \
  'proxmox_virtual_environment_download_file.ubuntu_cloud_image["bahamut"]'
```

### Verification

```bash
cd terraform/proxmox/images
terraform plan
```
Expected: 1 resource to add (eiko image download), 0 to destroy. The existing bahamut image should show no changes.

### STOP — Ask me to confirm before proceeding to Stage 2

---

## Stage 2: Refactor Terraform VMs Module for Multi-VM

**Goal:** Convert the VMs module from single-VM variables to a `for_each` map so it can manage N VMs.

### Files to modify

**`terraform/proxmox/vms/variables.tf`** — replace all single VM variables with a `vms` map. Keep Proxmox connection variables unchanged. Remove: `proxmox_node`, `proxmox_storage_vm`, `vm_name`, `vm_id`, `vm_username`, `vm_ssh_public_key`, `vm_ip`, `vm_gateway`, `vm_dns`, `vm_bridge`. Add:
```hcl
variable "vm_ssh_public_key" {
  description = "SSH public key for passwordless authentication"
  type        = string
  sensitive   = true
}

variable "vms" {
  description = "Map of VM definitions keyed by hostname"
  type = map(object({
    node_name = string
    vm_id     = number
    ip        = string
    gateway   = string
    cpu_cores = optional(number, 2)
    memory    = optional(number, 4096)
    disk_size = optional(number, 16)
    dns       = optional(string, "1.1.1.1")
    bridge    = optional(string, "vmbr0")
    storage   = optional(string, "local-lvm")
    username  = optional(string, "ubuntu")
  }))
}
```

**`terraform/proxmox/vms/terraform.tfvars`** — replace single VM values with the map:
```hcl
vms = {
  ubuntu-01 = {
    node_name = "bahamut"
    vm_id     = 200
    ip        = "192.168.1.130/24"
    gateway   = "192.168.1.1"
    memory    = 8192
  }
  monitoring-01 = {
    node_name = "eiko"
    vm_id     = 201
    ip        = "192.168.1.150/24"
    gateway   = "192.168.1.1"
    memory    = 2048
  }
}
```

**`terraform/proxmox/vms/main.tf`** — refactor both resources to use `for_each`:
```hcl
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
```
Keep the `terraform {}`, `provider "proxmox" {}`, and `data "terraform_remote_state" "images" {}` blocks unchanged — but update the remote state reference from `.outputs.ubuntu_cloud_image_id` to `.outputs.ubuntu_cloud_image_ids` (the new map output).

**`terraform/proxmox/vms/outputs.tf`** — output all VMs:
```hcl
output "vms" {
  description = "Map of VM details"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => {
      vm_id = vm.vm_id
      name  = vm.name
      ip    = var.vms[name].ip
    }
  }
}
```

### State migration

```bash
cd terraform/proxmox/vms
terraform state mv \
  'proxmox_virtual_environment_file.vendor_cloud_init' \
  'proxmox_virtual_environment_file.vendor_cloud_init["ubuntu-01"]'
terraform state mv \
  'proxmox_virtual_environment_vm.vm' \
  'proxmox_virtual_environment_vm.vm["ubuntu-01"]'
```

### Verification

```bash
cd terraform/proxmox/vms
terraform plan
```
Expected: Resources to add for monitoring-01 (cloud-init file + VM). No changes to ubuntu-01.

### STOP — Ask me to confirm before proceeding to Stage 3

---

## Stage 3: Apply Terraform — Provision the Monitoring VM

**Goal:** Download the cloud image to eiko and create the monitoring-01 VM.

### Steps

1. Apply images module:
```bash
cd terraform/proxmox/images
terraform apply
```

2. Apply VMs module:
```bash
cd terraform/proxmox/vms
terraform apply
```

3. Wait for cloud-init to complete (~2-3 minutes), then verify SSH:
```bash
ssh ubuntu@192.168.1.150 'docker --version && echo "OK"'
```

### STOP — Ask me to confirm before proceeding to Stage 4

---

## Stage 4: Ansible Inventory + Playbook for monitoring-01

**Goal:** Register the new VM in Ansible and create its playbook.

### Files to modify

**`ansible/inventory.yml`** — add monitoring_servers group:
```yaml
all:
  hosts:
    ubuntu-01:
      ansible_host: 192.168.1.130
      ansible_user: ubuntu
    bahamut:
      ansible_host: 192.168.1.101
      ansible_user: root
    monitoring-01:
      ansible_host: 192.168.1.150
      ansible_user: ubuntu
  children:
    app_servers:
      hosts:
        ubuntu-01:
    file_servers:
      hosts:
        bahamut:
    monitoring_servers:
      hosts:
        monitoring-01:
```

### Files to create

**`ansible/playbooks/monitoring-01.yml`**:
```yaml
---
- hosts: monitoring_servers
  become: true
  roles:
    - role: monitoring
      tags: monitoring
```

### Verification

```bash
cd ansible
ansible monitoring_servers -m ping
```
Expected: monitoring-01 responds with pong.

### STOP — Done! Continue with the Grafana monitoring implementation plan.
