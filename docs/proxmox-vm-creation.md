# Create Proxmox VMs from a cloud image

The VM tool creates each VM directly from the Ubuntu cloud image registered as
Proxmox `import` content. It does not use Terraform, Ansible, or a VM template.
Each VM receives an independent boot disk and its own cloud-init settings.

## Current Proxmox defaults

`vm-definitions/images.json` lists available images by identifier. The current
entry is `ubuntu-26.04-server-amd64`, which points to the image on `bahamut`:

```text
local:import/ubuntu-26.04-server-cloudimg-amd64.img.raw
```

The image is on `local` storage, which is node-local. The current target disk
storage is `local-lvm`, and the default network bridge is `vmbr0`. These defaults
target `bahamut`; the same image volume is not available on `eiko` unless it is
copied there or moved to shared storage.

## Add a VM definition

Copy `vm-definitions/app-01.json`, then set a free VM ID, hostname, node, image
identifier, resources, network address, and SSH public key path. Add other
available disk images to `vm-definitions/images.json`, each with a unique
identifier and Proxmox import volume. Do not put API tokens or private SSH keys
in a VM definition.

The tool reads the Proxmox API token from `TF_VAR_proxmox_api_token` in the
environment. If it is not set, the tool reads that variable from `fnox.toml`
using `fnox get`. TLS verification is disabled in the sample defaults to match
the existing Proxmox configuration; set `verify_tls` to `true` when the API
certificate is trusted by the machine running the tool.

## Validate and create

From the repository root:

```bash
node scripts/proxmox-vm.mjs validate vm-definitions/app-01.json
node scripts/proxmox-vm.mjs create vm-definitions/app-01.json
```

Validation checks the VM definition, SSH public key, node, target storage,
import image, and VM ID against the live Proxmox API, then prints the resolved
machine, network, image, and cloud-init settings in a readable summary. `create`
repeats those checks, prints the same summary, creates the VM and imported disk
in one API operation, waits for the import task, then starts the VM. Proxmox
cloud-init uses the username, SSH key, and network settings from the definition
on first boot.

The API token needs permission to audit the cluster and target node/storage,
allocate the VM and target disk, configure the VM and cloud-init, and start the
VM. A token with privilege separation also needs a backing user with the same
permissions.
