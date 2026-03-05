# Learning Roadmap: Terraform Multi-Node & Multi-VM Refactoring

This document is the companion to the implementation plan. Each section maps to an implementation stage — read the relevant section **before** executing that stage to understand the concepts behind what we're building.

---

## Stage 1 & 2: Terraform Multi-Resource Refactoring

### What we're doing
Converting the Terraform setup from managing a single VM to managing multiple VMs across multiple Proxmox nodes, using `for_each`.

### Key Concepts

#### Terraform `for_each` meta-argument
Every Terraform resource creates one infrastructure object by default. The `for_each` meta-argument tells Terraform to create **multiple instances** of a resource, one per item in a map or set.

Each instance gets a unique key in the Terraform state:
```
# Single resource (before)
proxmox_virtual_environment_vm.vm

# for_each resource (after)
proxmox_virtual_environment_vm.vm["ubuntu-01"]
proxmox_virtual_environment_vm.vm["monitoring-01"]
```

Inside the resource block, you access the current item with:
- `each.key` — the map key (e.g., `"ubuntu-01"`)
- `each.value` — the map value (the object with node_name, vm_id, ip, etc.)

#### Why `for_each` over `count`
`count` uses numeric indices (0, 1, 2...). If you define 3 VMs and remove the first one, items at index 1 and 2 shift to 0 and 1. Terraform sees this as "destroy old 1, create new 0" — it would **recreate** VMs that didn't change.

`for_each` uses string keys (`"ubuntu-01"`, `"monitoring-01"`). Removing `"ubuntu-01"` has no effect on `"monitoring-01"`. Each resource is independently addressable.

**Rule of thumb:** Use `count` only when resources are truly interchangeable (e.g., 3 identical worker nodes). Use `for_each` when each resource has a unique identity.

#### Terraform `optional()` type constraint
When defining an `object` type for a variable, `optional(type, default)` marks a field as not-required:

```hcl
variable "vms" {
  type = map(object({
    node_name = string                    # Required — no default
    memory    = optional(number, 4096)    # Optional — defaults to 4096
  }))
}
```

This lets you define only what's different per VM while sharing sensible defaults. In our case, most VMs will use the same CPU count (2), DNS (1.1.1.1), and bridge (vmbr0) — only memory and node differ.

#### Terraform state and `terraform state mv`
Terraform tracks every managed resource in a **state file** (`terraform.tfstate`). The state maps resource addresses (like `proxmox_virtual_environment_vm.vm`) to real infrastructure (VM ID 200 on Proxmox).

When you refactor from a single resource to `for_each`, the address changes:
```
Before: proxmox_virtual_environment_vm.vm
After:  proxmox_virtual_environment_vm.vm["ubuntu-01"]
```

Without intervention, Terraform would see the old address as "deleted" and the new one as "needs creation" — it would **destroy and recreate** your existing VM.

`terraform state mv` renames a resource in the state file without touching infrastructure:
```bash
terraform state mv \
  'proxmox_virtual_environment_vm.vm' \
  'proxmox_virtual_environment_vm.vm["ubuntu-01"]'
```

After this, Terraform recognizes the existing VM under its new address. No destruction.

#### `terraform_remote_state` data source
Our setup has two independent Terraform configurations: `images/` (downloads cloud images) and `vms/` (creates VMs). The `vms/` module needs the cloud image ID from `images/`.

`terraform_remote_state` reads another configuration's state file:
```hcl
data "terraform_remote_state" "images" {
  backend = "local"
  config = { path = "../images/terraform.tfstate" }
}

# Usage:
file_id = data.terraform_remote_state.images.outputs.ubuntu_cloud_image_ids[each.value.node_name]
```

This creates a **loose coupling** — both modules are independent (separate `terraform apply`), but the VMs module reads the image IDs it needs from the images module's outputs.

### Alternatives worth knowing about
- **Terraform workspaces**: Separate state files per environment (dev/staging/prod). Not useful for "same environment, multiple resources of different types."
- **Terragrunt**: A wrapper that reduces Terraform boilerplate for large multi-module setups. Useful when you have 20+ modules; overkill for a home lab.
- **OpenTofu**: An open-source fork of Terraform with identical syntax. Drop-in replacement if you care about open-source licensing (Terraform switched to BSL in 2023).

---

## Stage 3: Provisioning VMs with Cloud Images and Cloud-Init

### What we're doing
Running `terraform apply` to create a new VM on the `eiko` Proxmox node using a cloud image + cloud-init.

### Key Concepts

#### Proxmox QEMU/KVM virtualization
Proxmox uses **KVM** (Kernel-based Virtual Machine) to run full virtual machines. Each VM gets:
- Its own **kernel** (unlike Docker containers which share the host kernel)
- Its own **filesystem** (a virtual disk)
- Its own **network stack** (virtual NIC bridged to the physical network)
- Dedicated **CPU and memory** allocation

This provides **hardware-level isolation** — a crash in one VM doesn't affect others. The trade-off vs containers is higher resource overhead (each VM runs a full OS).

#### Cloud images
Traditional OS installation involves booting from an ISO, clicking through an installer, and waiting 20-30 minutes. **Cloud images** skip all of this.

A cloud image is a pre-built, minimal OS disk (~600MB) ready to boot. Ubuntu publishes these at `cloud-images.ubuntu.com`. The workflow:
1. Download the image once
2. Clone it for each new VM (Proxmox does this automatically)
3. Customize at first boot via cloud-init

This is how AWS/GCP/Azure launch VMs in seconds — they use the same concept.

#### Cloud-init
Cloud-init is the industry standard for **first-boot VM configuration**. When a VM boots for the first time, cloud-init:
1. Sets the hostname
2. Creates user accounts and injects SSH keys
3. Configures networking (static IP, gateway, DNS)
4. Installs packages
5. Runs custom scripts

In our setup, the `vendor-cloud-init.yaml` template installs Docker, qemu-guest-agent, and adds the ubuntu user to the docker group. Proxmox passes cloud-init config to the VM via a virtual CD-ROM drive that cloud-init reads on boot.

Cloud-init runs **only once**. After first boot, the VM is configured and cloud-init doesn't re-run (unless you clear its state).

#### Proxmox storage model
Each Proxmox node has **local storage** (datastores). Common types:
- `local` — directory-based, for ISOs and snippets
- `local-lvm` — LVM thin-provisioned, for VM disks

In a cluster, nodes share a unified API but storage is typically node-local. A cloud image on `bahamut:local` is **not accessible** to VMs on `eiko`. That's why Stage 1 downloads the image to both nodes.

Shared storage (Ceph, NFS) eliminates this constraint but adds complexity. For a 2-node home lab, duplicating a 600MB image is simpler.

#### `qemu-guest-agent`
A small daemon inside the VM that communicates with the Proxmox host. Without it, Proxmox can only hard-power-off VMs. With it:
- **Graceful shutdown** — Proxmox sends a shutdown signal the VM handles cleanly
- **IP reporting** — Proxmox knows the VM's IP address (shown in the web UI)
- **Filesystem freeze** — Enables consistent snapshots

#### Why a separate VM for monitoring
If monitoring runs on the same machine it monitors, you lose visibility exactly when you need it most — when that machine is down. Running monitoring on a separate VM/node means:
- Monitoring stays up even if `ubuntu-01` crashes
- Resources don't compete (a large backup won't starve Prometheus of CPU)
- Clean separation of concerns

---

## Stage 4: Ansible Inventory and Playbooks

### What we're doing
Adding the new monitoring-01 VM to Ansible's inventory and creating a playbook that maps it to the monitoring role.

### Key Concepts

#### Ansible inventory
The inventory file answers: **"What machines exist and how do I connect to them?"**

```yaml
all:
  hosts:
    ubuntu-01:
      ansible_host: 192.168.1.130    # IP address
      ansible_user: ubuntu            # SSH user
    monitoring-01:
      ansible_host: 192.168.1.150
      ansible_user: ubuntu
  children:
    app_servers:                      # Group
      hosts:
        ubuntu-01:
    monitoring_servers:               # Group
      hosts:
        monitoring-01:
```

Machines are organized into **groups**. Groups let you target multiple machines at once (`ansible app_servers -m ping`) and apply roles to logical collections rather than individual hosts.

#### Ansible playbooks
A playbook answers: **"What should be configured on which machines?"**

```yaml
- hosts: monitoring_servers     # Target group
  become: true                  # Run as root (sudo)
  roles:
    - role: monitoring          # Apply this role
      tags: monitoring          # Can be filtered with --tags
```

Playbooks are **declarative** — you describe the desired state ("Docker Compose file should exist at this path, containers should be running") rather than imperative steps ("copy file, then run docker"). Ansible figures out what needs to change.

#### Ansible roles
Roles are **reusable automation packages** with a standard structure:
```
roles/monitoring/
├── defaults/main.yml    # Default variable values (lowest priority)
├── tasks/main.yml       # What to do (the main logic)
├── templates/           # Jinja2 templates (files with {{ variable }} substitution)
└── files/               # Static files to copy as-is
```

Each service in your home lab (jellyfin, restic, homepage, monitoring) gets its own role. Roles are composable — a playbook can apply multiple roles to the same host.

#### Tags
Tags let you selectively run parts of a playbook:
```bash
# Run everything in the playbook
ansible-playbook playbooks/monitoring-01.yml

# Run only tasks/roles tagged "monitoring"
ansible-playbook playbooks/monitoring-01.yml --tags monitoring
```

This is how `mise run monitoring:up` works — it runs the playbook but filters to just the monitoring tag. Useful when you have multiple roles in one playbook and only want to update one.

---

## Summary: Concept Map

```
┌─ Infrastructure Layer ────────────────────────────────┐
│  Terraform (for_each, state, remote_state)            │
│  → Proxmox KVM (cloud images, cloud-init)             │
│  → VM provisioning (monitoring-01 on eiko)            │
└───────────────────────────────────────────────────────┘
         │
         ▼
┌─ Configuration Layer ─────────────────────────────────┐
│  Ansible (inventory, playbooks, roles, tags)          │
│  → Docker Compose (services, volumes, networks)       │
│  → fnox/age (secrets management)                      │
│  → mise (task runner)                                 │
└───────────────────────────────────────────────────────┘
```
