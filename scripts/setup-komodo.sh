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
curl -fsSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py | python3 - \
  --version=v2.3.3 \
  --core-address=ws://192.168.1.130:9120 \
  --connect-as="$server_name" \
  --onboarding-key="$onboarding_key"
unset onboarding_key
systemctl enable --now periphery
systemctl is-active --quiet periphery
systemctl is-enabled --quiet periphery
printf 'Periphery is installed, active, and enabled as %s.\n' "$server_name"
REMOTE_SCRIPT
} | ssh "ubuntu@$server_ip" sudo -n bash -s

unset onboarding_key
printf '\nConfirm the VM appears healthy in Komodo. Then remove onboarding_key from\n'
printf '/etc/komodo/periphery.config.toml, restart Periphery, and revoke the\n'
printf 'temporary onboarding key in Komodo Settings → Onboarding Keys.\n'
