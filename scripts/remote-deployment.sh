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

remote_container_dir="$(jq -r '.remote_dir // empty' "$config_file")"
if [[ -z "$remote_container_dir" ]]; then
  remote_container_dir="/home/ubuntu/compose/$container_name"
elif [[ "$remote_container_dir" != /* || "$remote_container_dir" == *..* || "$remote_container_dir" == *[[:space:]]* ]]; then
  echo "remote_dir must be an absolute path without whitespace in $config_file" >&2
  exit 1
fi

port="$(jq -er '.port | numbers | select(. >= 1 and . <= 65535 and floor == .)' "$config_file")"
mapfile -t item_paths < <(jq -er '.items // [] | .[] | select(.type == "folder") | .path | strings | select(length > 0)' "$config_file")
if (( ${#item_paths[@]} > 0 )); then
  container_data="$(awk -F= '$1 == "CONTAINERS_DATA" {sub(/^[^=]*=/, ""); print; exit}' "$env_file")"
  if [[ -z "$container_data" || "$container_data" != /* || "$container_data" == *[[:space:]]* ]]; then
    echo "CONTAINERS_DATA must be an absolute path without whitespace in $env_file" >&2
    exit 1
  fi
fi

for item_path in "${item_paths[@]}"; do
  if [[ "$item_path" = /* || "$item_path" == *..* || "$item_path" == *[[:space:]]* ]]; then
    echo "Deployment item paths must be relative and contain no whitespace: $item_path" >&2
    exit 1
  fi
done

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

for item_path in "${item_paths[@]}"; do
  source_dir="$compose_dir/$item_path"
  if [[ ! -d "$source_dir" ]]; then
    echo "Deployment source directory not found: $source_dir" >&2
    exit 1
  fi

  echo "Copying deployment item: $item_path"
  ssh "$ssh_target" "mkdir -p '$container_data/$item_path'"
  scp -r "$source_dir/." "$ssh_target:$container_data/$item_path/"
done

echo "Starting $container_name remotely..."
ssh "$ssh_target" "cd '$remote_container_dir' && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml pull && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml up -d"

printf '\033[0;32mDone!\033[0m\n'
