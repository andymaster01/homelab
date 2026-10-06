#!/usr/bin/env bash

set -euo pipefail

read -r -p 'VM IPv4 address: ' server_ip
if [[ ! "$server_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  echo "Invalid IPv4 address: $server_ip" >&2
  exit 1
fi
IFS=. read -r -a octets <<< "$server_ip"
for octet in "${octets[@]}"; do
  if (( 10#$octet > 255 )); then
    echo "Invalid IPv4 address: $server_ip" >&2
    exit 1
  fi
done

echo "Checking Komodo Periphery on ubuntu@$server_ip..."
ssh "ubuntu@$server_ip" sudo -n bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

if [[ ! -x /usr/local/bin/periphery || ! -s /etc/komodo/periphery.config.toml || ! -f /etc/systemd/system/periphery.service ]]; then
  echo 'WARNING: Komodo Periphery is not fully installed and configured on this VM.' >&2
  echo 'Run `just setup-komodo` to install and onboard it.' >&2
  exit 1
fi

if ! systemctl is-enabled --quiet periphery; then
  echo 'Periphery is installed but disabled; enabling it.'
  systemctl enable periphery
fi

if ! systemctl is-active --quiet periphery; then
  echo 'Periphery is stopped; starting it.'
  systemctl start periphery
fi

systemctl is-enabled --quiet periphery
systemctl is-active --quiet periphery
printf 'Periphery is configured, enabled, and running on %s.\n' "$(hostname -s)"
REMOTE_SCRIPT
