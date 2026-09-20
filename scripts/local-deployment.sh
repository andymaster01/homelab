#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 <container-name>" >&2
  exit 1
fi

container_name="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
compose_dir="$repo_root/containers/$container_name"
compose_file="$compose_dir/docker-compose.yml"
env_file="$compose_dir/.env.local"
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
  echo "Configuration file not found: $config_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $config_file" >&2
  exit 1
fi

port="$(jq -er '.port | numbers | select(. >= 1 and . <= 65535 and floor == .)' "$config_file")"
mapfile -t item_paths < <(jq -er '.items // [] | .[] | select(.type == "folder") | .path | strings | select(length > 0)' "$config_file")
if (( ${#item_paths[@]} > 0 )); then
  container_data="$(awk -F= '$1 == "CONTAINERS_DATA" {sub(/^[^=]*=/, ""); print; exit}' "$env_file")"
  if [[ -z "$container_data" ]]; then
    echo "CONTAINERS_DATA is required in $env_file when deployment items are configured" >&2
    exit 1
  fi

  if [[ "$container_data" = /* ]]; then
    container_data_dir="$container_data"
  else
    container_data_dir="$compose_dir/$container_data"
  fi
  mkdir -p "$container_data_dir"
  container_data_dir="$(cd -- "$container_data_dir" && pwd)"
fi

for item_path in "${item_paths[@]}"; do
  if [[ "$item_path" = /* || "$item_path" == *..* || "$item_path" == *[[:space:]]* ]]; then
    echo "Deployment item paths must be relative and contain no whitespace: $item_path" >&2
    exit 1
  fi

  source_dir="$compose_dir/$item_path"
  destination_dir="$container_data_dir/$item_path"
  if [[ ! -d "$source_dir" ]]; then
    echo "Deployment source directory not found: $source_dir" >&2
    exit 1
  fi

  echo "Copying deployment item: $item_path"
  mkdir -p "$destination_dir"
  cp -R "$source_dir/." "$destination_dir/"
done

if docker container inspect "$container_name" >/dev/null 2>&1 && [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" == "true" ]]; then
  echo "Stopping running container: $container_name"
  docker stop "$container_name"
fi

echo "Deploying $container_name locally..."
PORT="$port" docker compose \
  --env-file "$env_file" \
  -f "$compose_file" \
  up -d

echo "Deployment complete: $container_name"
