# Onboard a new VM into Komodo

This runbook installs Komodo Periphery on a new Ubuntu VM and connects it to
the Komodo Core running at `192.168.1.130:9120`. The current Core and Periphery
version is `2.3.3`; keep Periphery compatible with the Core version.

## 1. Create a temporary onboarding key

1. Sign in to Komodo at `http://192.168.1.130:9120`.
2. Open **Settings → Onboarding Keys** and create a key for this VM.
3. Give it a short expiry and a descriptive name. Create a separate key for
   each VM and leave privileged access disabled unless Komodo specifically
   requires it for an existing server.
4. Copy the private onboarding key when Komodo displays it. It is only shown
   once. Do not put it in Git, a saved script, or shell history.

## 2. Install Periphery

From the repository root, run the interactive recipe:

```bash
just setup-komodo
```

It prompts for the new VM's IPv4 address and onboarding key, then connects over
SSH as `ubuntu`, uses the VM hostname as its Komodo server name, and installs
Periphery `2.3.3`. The SSH account must have non-interactive `sudo` access for
the install. If Periphery is already installed, this recipe refreshes the Core
address, server name, and onboarding key in its existing config before
restarting the service.

To install manually instead, SSH to the new Ubuntu VM. Replace `new-vm-name`
with the name to show in Komodo. Enter the onboarding key at the hidden prompt
so it is not written into shell history:

```bash
set -e
read -rsp 'Onboarding key: ' KOMODO_ONBOARDING_KEY; printf '\n'
sudo env KOMODO_ONBOARDING_KEY="$KOMODO_ONBOARDING_KEY" bash -c 'curl -fsSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - \
  --version=v2.3.3 \
  --core-address=ws://192.168.1.130:9120 \
  --connect-as=new-vm-name \
  --onboarding-key="$KOMODO_ONBOARDING_KEY"'
unset KOMODO_ONBOARDING_KEY
sudo systemctl enable --now periphery
```

The installer creates the `periphery` systemd service and its configuration.
The key is temporarily stored in `/etc/komodo/periphery.config.toml` to complete
onboarding. Keep SSH access to the VM and do not share command output that may
include the key.

## 3. Confirm the VM connected

In Komodo, confirm the new server appears with the intended name and reports a
healthy connection. On the VM, check the service state:

```bash
systemctl is-active periphery
systemctl is-enabled periphery
```

Both commands should report `active` and `enabled`. If it is not healthy, inspect
the recent startup logs:

```bash
sudo journalctl -u periphery -n 100 --no-pager
```

Check that the VM can reach `192.168.1.130` on port `9120`, and that the Core
address, server name, and Periphery version are correct.

For a VM that already has Periphery installed and configured, run
`just enable-komodo`. It prompts for the VM's IP, warns if the Periphery binary,
configuration, or systemd service is missing, and enables and starts the service
when needed. It checks local systemd state only; confirm that the server reports
healthy in Komodo to verify the onboarding handshake succeeded.

## 4. Remove the temporary onboarding key

After the server has connected, remove the onboarding key from Periphery's
configuration and restart the service:

```bash
sudo sed -i '/^[[:space:]]*onboarding_key[[:space:]]*=/d' /etc/komodo/periphery.config.toml
sudo systemctl restart periphery
```

Confirm it remains connected in Komodo, then delete or revoke the onboarding
key in **Settings → Onboarding Keys**. Recheck `systemctl is-active periphery`
after the restart.

## Notes

- Existing Ubuntu VMs already include systemd; this procedure installs
  Periphery as a systemd service, it does not install systemd itself.
- Periphery connects outbound to Core over WebSocket, so the VM needs network
  access to `192.168.1.130:9120`.
- The VM can run on a different Proxmox node from Komodo Core. Proxmox cluster
  placement does not affect onboarding; the VM's network must route to the Core
  address and allow outbound TCP port `9120` (including the WebSocket
  connection). If the VM is on another VLAN or subnet, configure routing and
  firewall rules between it and Core first.
- The setup script is downloaded from Komodo's official repository. Review it
  before running if the VM has different security or change-control
  requirements.

See Komodo's [Connect more servers guide](https://komo.do/docs/setup/connect-servers)
for the current onboarding workflow and setup script options.
