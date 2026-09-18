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
config_file="$repo_root/containers/$container_name/config.json"

if [[ ! -f "$config_file" ]]; then
  echo "Configuration file not found: $config_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $config_file" >&2
  exit 1
fi

remote_host="$(jq -er '.remote | strings | select(length > 0)' "$config_file")"
stop_container="$(jq -er '.backup.stopContainer | booleans' "$config_file")"
destination="$(jq -er '.backup.destination | strings | select(startswith("/"))' "$config_file")"
retention="$(jq -er '.backup.retention | numbers | select(. >= 1 and floor == .)' "$config_file")"
mapfile -t item_paths < <(jq -er '.backup.items[] | select(.type == "folder") | .path | select(startswith("/"))' "$config_file")

if [[ ${#item_paths[@]} -eq 0 ]]; then
  echo "No folder backup items configured in: $config_file" >&2
  exit 1
fi

for item_path in "${item_paths[@]}"; do
  if [[ "$item_path" == *[[:space:]]* ]]; then
    echo "Backup paths containing whitespace are not supported: $item_path" >&2
    exit 1
  fi
done

ssh_target="ubuntu@$remote_host"

echo "Starting backup of $container_name on $ssh_target..."
ssh "$ssh_target" bash -s -- \
  "$container_name" \
  "$stop_container" \
  "$destination" \
  "$retention" \
  "${item_paths[@]}" <<'REMOTE_SCRIPT'
set -euo pipefail

container_name="$1"
stop_container="$2"
destination="$3"
retention="$4"
shift 4
item_paths=("$@")
stopped_by_backup=false

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required on the remote server" >&2
  exit 1
fi

restart_container() {
  if [[ "$stopped_by_backup" == true ]]; then
    echo "Starting container: $container_name"
    docker start "$container_name" >/dev/null
  fi
}

trap restart_container EXIT

if [[ "$stop_container" == true ]] && docker container inspect "$container_name" >/dev/null 2>&1 && [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" == true ]]; then
  echo "Stopping container: $container_name"
  docker stop "$container_name" >/dev/null
  stopped_by_backup=true
fi

mkdir -p "$destination"

shopt -s nullglob
backup_files=("$destination"/"$container_name"-*.zip)
while (( ${#backup_files[@]} >= retention )); do
  oldest_backup="$(ls -1tr -- "${backup_files[@]}" | head -n 1)"
  echo "Removing old backup: $oldest_backup"
  rm -f -- "$oldest_backup"
  backup_files=("$destination"/"$container_name"-*.zip)
done

archive_path="$destination/$container_name-$(date '+%Y-%H%M%S').zip"
temporary_archive="$archive_path.tmp"
relative_paths=()

for item_path in "${item_paths[@]}"; do
  if [[ ! -d "$item_path" ]]; then
    echo "Backup source directory not found: $item_path" >&2
    exit 1
  fi
  relative_paths+=("${item_path#/}")
done

echo "Creating backup: $archive_path"
(cd / && zip -q -r "$temporary_archive" "${relative_paths[@]}")
mv -- "$temporary_archive" "$archive_path"
echo "Backup created: $archive_path"
REMOTE_SCRIPT

printf '\033[0;32mDone!\033[0m\n'
