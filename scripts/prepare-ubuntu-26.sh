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

echo "Preparing Ubuntu 26.04 on $ssh_target..."
ssh "$ssh_target" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

sudo apt-get update
sudo apt-get install -y ca-certificates curl jq zip

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
ubuntu_suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
architecture="$(dpkg --print-architecture)"
if [[ "$ubuntu_suite" != "resolute" ]]; then
  echo "Expected Ubuntu 26.04 (resolute), found ${ubuntu_suite:-unknown}" >&2
  exit 1
fi

docker_source="/etc/apt/sources.list.d/docker.sources"
sudo tee "$docker_source" >/dev/null <<DOCKER_SOURCE
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_suite
Components: stable
Architectures: $architecture
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_SOURCE

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

group_added=0
if ! id -nG ubuntu | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker ubuntu
  group_added=1
fi

sudo systemctl enable --now docker

echo "Installed versions:"
jq --version
zip -v | head -n 1
docker --version
docker compose version
sudo systemctl is-active docker
sudo -u ubuntu docker info --format 'Docker server {{.ServerVersion}}'

if (( group_added )); then
  echo "Added ubuntu to the docker group. Reconnect over SSH for group access to take effect."
fi
REMOTE_SCRIPT

printf '\033[0;32mUbuntu 26.04 preparation complete!\033[0m\n'
