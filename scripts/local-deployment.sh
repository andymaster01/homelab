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
if ! jq -e '
  def required_string: type == "string" and length > 0;
  (.volume_seeds // [])
  | type == "array"
    and all(.[]; type == "object"
      and (.source | required_string)
      and (.service | required_string)
      and (.target | required_string))
' "$config_file" >/dev/null; then
  echo "volume_seeds must be an array of entries with source, service, and target strings in $config_file" >&2
  exit 1
fi
mapfile -t volume_seeds < <(jq -r '.volume_seeds // [] | .[] | [.source, .service, .target] | @tsv' "$config_file")
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

for volume_seed in "${volume_seeds[@]}"; do
  IFS=$'\t' read -r seed_source seed_service seed_target <<< "$volume_seed"
  if [[ "$seed_source" = /* || "$seed_source" == *..* || "$seed_source" == *[[:space:]]* ]]; then
    echo "Volume seed source must be relative and contain no whitespace: $seed_source" >&2
    exit 1
  fi
  if [[ ! "$seed_service" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    echo "Invalid volume seed service: $seed_service" >&2
    exit 1
  fi
  if [[ "$seed_target" != /* || "$seed_target" == *..* || "$seed_target" == *[[:space:]]* ]]; then
    echo "Volume seed target must be an absolute path without whitespace: $seed_target" >&2
    exit 1
  fi
  if [[ ! -d "$compose_dir/$seed_source" ]]; then
    echo "Volume seed source directory not found: $compose_dir/$seed_source" >&2
    exit 1
  fi
done

if docker container inspect "$container_name" >/dev/null 2>&1 && [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" == "true" ]]; then
  echo "Stopping running container: $container_name"
  docker stop "$container_name"
fi

for volume_seed in "${volume_seeds[@]}"; do
  IFS=$'\t' read -r seed_source seed_service seed_target <<< "$volume_seed"

  echo "Creating service container for volume seed: $seed_service"
  PORT="$port" docker compose \
    --env-file "$env_file" \
    -f "$compose_file" \
    create "$seed_service"

  seed_container_id="$(PORT="$port" docker compose --env-file "$env_file" -f "$compose_file" ps -aq "$seed_service" | head -n 1)"
  if [[ -z "$seed_container_id" ]]; then
    echo "Volume seed service container not found: $seed_service" >&2
    exit 1
  fi

  if ! docker inspect "$seed_container_id" | jq -e --arg target "$seed_target" \
    '.[0].Mounts[] | select(.Destination == $target and .Type == "volume") | .Name' >/dev/null; then
    echo "Volume seed target is not a named volume mount for $seed_service: $seed_target" >&2
    exit 1
  fi

  echo "Seeding $seed_source into $seed_service:$seed_target"
  docker cp "$compose_dir/$seed_source/." "$seed_container_id:$seed_target/"
done

echo "Deploying $container_name locally..."
PORT="$port" docker compose \
  --env-file "$env_file" \
  -f "$compose_file" \
  up -d

echo "Deployment complete: $container_name"
