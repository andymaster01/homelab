#!/usr/bin/env bash

set -euo pipefail

read -r -p 'New VM IPv4 address: ' server_ip
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

read -r -s -p 'Komodo onboarding key: ' onboarding_key
printf '\n'
if [[ -z "$onboarding_key" ]]; then
  echo 'The onboarding key cannot be empty.' >&2
  exit 1
fi

echo "Installing Komodo Periphery on ubuntu@$server_ip..."
{
  # Stream the key over SSH stdin instead of placing it in shell history or
  # the local ssh command arguments. printf %q creates a valid Bash assignment.
  printf 'onboarding_key=%q\n' "$onboarding_key"
  cat <<'REMOTE_SCRIPT'
set -euo pipefail
server_name="$(hostname -s)"
had_periphery_unit=false
if [[ -f /etc/systemd/system/periphery.service ]]; then
  had_periphery_unit=true
fi

# The upstream installer leaves an existing config untouched, so refresh its
# Core address, server name, and temporary onboarding key before reinstalling.
if [[ -f /etc/komodo/periphery.config.toml ]]; then
  export onboarding_key
  export KOMODO_SERVER_NAME="$server_name"
  python3 - <<'PY'
import json
import os
import re
from pathlib import Path

path = Path('/etc/komodo/periphery.config.toml')
values = {
    'core_address': 'ws://192.168.1.130:9120',
    'connect_as': os.environ['KOMODO_SERVER_NAME'],
    'onboarding_key': os.environ['onboarding_key'],
}
pattern = re.compile(r'^\s*(core_address|connect_as|onboarding_key)\s*=')
lines = path.read_text().splitlines()
seen = set()
updated = []
for line in lines:
    match = pattern.match(line)
    if match:
        key = match.group(1)
        updated.append(f'{key} = {json.dumps(values[key])}')
        seen.add(key)
    else:
        updated.append(line)
for key, value in values.items():
    if key not in seen:
        updated.append(f'{key} = {json.dumps(value)}')
path.write_text('\n'.join(updated) + '\n')
PY
fi

curl -fsSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - \
  --version=v2.3.3 \
  --core-address=ws://192.168.1.130:9120 \
  --connect-as="$server_name" \
  --onboarding-key="$onboarding_key"
unset onboarding_key
systemctl enable --now periphery
if [[ "$had_periphery_unit" == true ]]; then
  systemctl restart periphery
fi
systemctl is-active --quiet periphery
systemctl is-enabled --quiet periphery
printf 'Periphery is installed, active, and enabled as %s.\n' "$server_name"
printf 'Confirm the server reports healthy in Komodo; systemd status alone does not verify onboarding.\n'
REMOTE_SCRIPT
} | ssh "ubuntu@$server_ip" sudo -n bash -s

unset onboarding_key
printf '\nConfirm the VM appears healthy in Komodo. Then remove onboarding_key from\n'
printf '/etc/komodo/periphery.config.toml, restart Periphery, and revoke the\n'
printf 'temporary onboarding key in Komodo Settings → Onboarding Keys.\n'
