# Proxmox development VM plan

## Goal

Keep the working copies of projects, Codex CLI, and AWS tools on one Ubuntu VM. Connect to the same VM from a Mac or Android phone, at home or while traveling, without a public IP or router port forwarding.

## Setup

1. **Create one VM in the Proxmox web interface.** Choose a node with the Ubuntu 24.04 cloud image available and create `dev-01` with 4 vCPUs, 8 GB RAM, and a 100 GB disk. Pick a free VM ID and LAN address after checking Proxmox and the router. Attach it to `vmbr0`, enable the QEMU guest agent, and set the cloud-init user to `ubuntu` with your SSH public key. Increase RAM or disk later if projects need it.
2. **Set up the development account.** Use the VM's `ubuntu` user, enable OpenSSH, and install Git, `tmux`, Codex CLI, AWS CLI v2, and only the language runtimes each project needs. Clone repositories under `~/code`; edit and run them on the VM. Sign in to Git, Codex, and AWS interactively on the VM. Prefer AWS IAM Identity Center profiles where available and keep credentials out of repositories. For headless Codex sign-in, use `codex login --device-auth` if enabled for the account.
3. **Join all three devices to one Tailscale network.** Install Tailscale on the VM, Mac, and Android phone and sign in to the same tailnet. Use the VM's MagicDNS name (for example, `dev-01`) for SSH from either location. Tailscale can connect through NAT or use a relay when direct connectivity is unavailable; no public IP or inbound router rule is required. Keep normal OpenSSH key authentication, with a separate key for the phone. Add the phone's public key to this VM's `~ubuntu/.ssh/authorized_keys` from the Mac after the first connection.
4. **Use each device.** On the Mac, connect with `ssh ubuntu@dev-01` or open `~/code` through VS Code Remote SSH. On Android, turn on Tailscale and use an SSH terminal app such as Termux to run `ssh ubuntu@dev-01`. Start work inside `tmux` so a Codex session survives a dropped phone or laptop connection; reconnect and run `tmux attach`. A phone provides a terminal workflow; the Mac provides the full editor.
5. **Protect the work.** Push committed code to its Git remote. Schedule a Proxmox backup for the VM so uncommitted work and local setup can be restored. Keep the VM, Tailscale, OS packages, and Codex updated. Do not expose SSH or a web IDE through port forwarding.

## Rollout checks

- In Proxmox, confirm the VM has the selected ID, address, resources, and cloud-init SSH key, then start it.
- From the Mac, confirm SSH and VS Code Remote SSH work over the home LAN and over a phone hotspot.
- From Android, confirm SSH and `tmux attach` work on home Wi-Fi and cellular data.
- Run `codex` and an AWS CLI profile check on the VM; confirm a small test repository is under `~/code` and included in a VM backup.

## References

- [Tailscale: install on Linux](https://tailscale.com/docs/install/linux), [Android](https://tailscale.com/docs/install/android), and [SSH over Tailscale](https://tailscale.com/docs/reference/ssh-over-tailscale)
- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh)
- [OpenAI Docs: Codex CLI](https://learn.chatgpt.com/docs/codex/cli) and [headless authentication](https://learn.chatgpt.com/docs/auth#login-on-headless-devices)
