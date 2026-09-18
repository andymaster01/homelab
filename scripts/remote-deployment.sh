#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 <container-name>" >&2
  exit 1
fi

container_name="$1"

if [[ ! "$container_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  echo "Invalid container name: $container_name" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
compose_dir="$repo_root/containers/$container_name"
compose_file="$compose_dir/docker-compose.yml"
env_file="$compose_dir/.env.remote"
config_file="$compose_dir/config.json"
remote_compose_root="/home/ubuntu/compose"
remote_container_dir="$remote_compose_root/$container_name"

if [[ ! -f "$compose_file" ]]; then
  echo "Compose file not found: $compose_file" >&2
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Environment file not found: $env_file" >&2
  exit 1
fi

if [[ ! -f "$config_file" ]]; then
  echo "Remote config not found: $config_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $config_file" >&2
  exit 1
fi

remote_host="$(jq -er '.remote | strings | select(length > 0)' "$config_file")"
ssh_target="ubuntu@$remote_host"

echo "Preparing $ssh_target..."
ssh "$ssh_target" "mkdir -p '$remote_container_dir'"

if ssh "$ssh_target" "docker container inspect '$container_name' >/dev/null 2>&1 && [ \"\$(docker inspect --format '{{.State.Running}}' '$container_name')\" = true ]"; then
  echo "Stopping running container: $container_name"
  ssh "$ssh_target" "docker stop '$container_name'"
fi

echo "Copying deployment files..."
scp "$compose_file" "$env_file" "$ssh_target:$remote_container_dir/"

echo "Starting $container_name remotely..."
ssh "$ssh_target" "cd '$remote_container_dir' && docker compose --env-file .env.remote -f docker-compose.yml pull && docker compose --env-file .env.remote -f docker-compose.yml up -d"

printf '\033[0;32mDone!\033[0m\n'
