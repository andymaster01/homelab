# Create an Ubuntu VM Template in Proxmox

This runbook turns an existing Ubuntu VM into a reusable Proxmox template with
cloud-init. Clones can receive their own hostname, SSH key, and network settings.

## 1. Back up the VM

Before changing the guest or converting it, create a Proxmox backup and confirm the
backup task completes successfully.

## 2. Install cloud-init in Ubuntu

Log in to the VM and install cloud-init:

```bash
sudo apt update
sudo apt install cloud-init
```

## 3. Add a Cloud-Init drive in Proxmox

Shut down the VM. In the Proxmox UI, select the VM and open **Hardware → Add →
CloudInit Drive**. Choose storage and add it. Then open the VM's **Cloud-Init** tab
and configure:

- **User** and password for the account clones should use
- **SSH public key** (paste the `.pub` key, never the private key)
- **IP Config (net0)** as DHCP, or enter a unique static address for each clone
- DNS settings if you don't want the cluster host settings

Keep the VM powered off until the guest configuration below is ready.

## 4. Remove Ubuntu installer settings that block Proxmox cloud-init

Ubuntu's installer may leave files that force the `None` datasource, disable
cloud-init networking, and recreate `/etc/cloud/cloud-init.disabled`. Check for
them:

```bash
sudo ls -l /etc/cloud/cloud-init.disabled
sudo ls /etc/cloud/cloud.cfg.d/
```

If these files exist, move them out of `cloud.cfg.d` so cloud-init no longer loads
them. Keeping them under `/etc/cloud` preserves a copy:

```bash
sudo mv /etc/cloud/cloud.cfg.d/99-installer.cfg /etc/cloud/99-installer.cfg.saved
sudo mv /etc/cloud/cloud.cfg.d/00-subiquity-disable-cloudinit-networking.cfg /etc/cloud/00-subiquity-disable-cloudinit-networking.cfg.saved
```

Remove the disable marker if it exists:

```bash
sudo rm /etc/cloud/cloud-init.disabled
```

The installer files are optional and their names can vary by Ubuntu release. Only
move a file if it exists. In particular, `99-installer.cfg` may contain
`datasource_list: [None]`, and the Subiquity networking file may contain
`network: {config: disabled}`. Both prevent Proxmox's NoCloud seed from fully
configuring a clone.

## 5. Reboot once to verify cloud-init

Clear cloud-init's old instance state, then reboot:

```bash
sudo cloud-init clean --logs --machine-id
sudo reboot
```

Use the Proxmox console after reboot; the VM may receive a new DHCP address. Check
that cloud-init used Proxmox's NoCloud drive, completed without errors, and has an
IPv4 address:

```bash
hostnamectl --static
sudo cloud-init status --long
ip -4 addr
```

Expected results include `status: done`, a detail line similar to
`DataSourceNoCloud [seed=/dev/sr0]`, and an IPv4 address on the network interface.
Cloud-init may label the result `degraded done` when Proxmox's generated user
configuration emits a deprecation warning; check that `errors` is empty and the
hostname and address are correct.

If you configured an SSH key, test logging in from the machine holding the private
key:

```bash
ssh <cloud-init-user>@<clone-ip-address>
```

## 6. Clean and convert the VM to a template

After successful verification, clear the instance state again so a clone is treated
as a new instance. Then shut down the VM:

```bash
sudo cloud-init clean --logs --machine-id
sudo shutdown -h now
```

When the VM is powered off in Proxmox, select **More → Convert to template** and
confirm.

## 7. Create and verify a clone

Right-click the template and choose **Clone**. Choose a unique VM ID and name. The
VM name is used as the cloud-init hostname, so enter the hostname you want there.
Choose:

- **Full clone** for an independent disk copy that uses more storage
- **Linked clone** for a faster, smaller clone that depends on the template disk

Before the clone's first boot, open its **Cloud-Init** tab. Set DHCP or a unique
static IP, and adjust the username, password, SSH key, or DNS if needed. Click
**Regenerate Image** after changing cloud-init settings, then start the clone.

Verify from the clone's console:

```bash
hostnamectl --static
sudo cloud-init status --long
ip -4 addr
```

The hostname should match the clone name, cloud-init should report `done`, and the
clone should have its own working network address.
