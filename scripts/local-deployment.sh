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

if [[ ! -f "$compose_file" ]]; then
  echo "Compose file not found: $compose_file" >&2
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Environment file not found: $env_file" >&2
  exit 1
fi

if docker container inspect "$container_name" >/dev/null 2>&1 && [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" == "true" ]]; then
  echo "Stopping running container: $container_name"
  docker stop "$container_name"
fi

echo "Deploying $container_name locally..."
docker compose \
  --env-file "$env_file" \
  -f "$compose_file" \
  up -d

echo "Deployment complete: $container_name"
