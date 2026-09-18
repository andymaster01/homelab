#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 <server-ip>" >&2
  exit 1
fi

server_ip="$1"

if [[ ! "$server_ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
  echo "Invalid IPv4 address: $server_ip" >&2
  exit 1
fi

ssh_target="ubuntu@$server_ip"

echo "Preparing $ssh_target..."
ssh "$ssh_target" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

packages=()

command -v jq >/dev/null 2>&1 || packages+=(jq)
command -v zip >/dev/null 2>&1 || packages+=(zip)
command -v docker >/dev/null 2>&1 || packages+=(docker.io)
docker compose version >/dev/null 2>&1 || packages+=(docker-compose-plugin)

if (( ${#packages[@]} > 0 )); then
  echo "Installing: ${packages[*]}"
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
fi

if ! id -nG ubuntu | tr ' ' '\n' | grep -qx docker; then
  echo "Adding ubuntu to the docker group"
  sudo usermod -aG docker ubuntu
  echo "Reconnect to SSH before using Docker without sudo."
fi

echo "Installed versions:"
jq --version
zip -v | head -n 1
docker --version
docker compose version
REMOTE_SCRIPT

printf '\033[0;32mDone!\033[0m\n'
