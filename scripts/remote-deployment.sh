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

if ! remote_container_dir="$(jq -er '.remote_dir | strings | select(length > 0)' "$config_file")"; then
  echo "remote_dir is required and must be an absolute path without whitespace in $config_file" >&2
  exit 1
fi
if [[ "$remote_container_dir" != /* || "$remote_container_dir" == *..* || "$remote_container_dir" == *[[:space:]]* ]]; then
  echo "remote_dir is required and must be an absolute path without whitespace in $config_file" >&2
  exit 1
fi

port="$(jq -er '.port | numbers | select(. >= 1 and . <= 65535 and floor == .)' "$config_file")"
item_paths=()
while IFS= read -r item_path; do
  item_paths+=("$item_path")
done < <(jq -er '.items // [] | .[] | select(.type == "folder") | .path | strings | select(length > 0)' "$config_file")
if ! jq -e '
  def valid_path: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._/-]*$") and (contains("..") | not);
  (.data_directories // [])
  | type == "array"
    and all(.[]; type == "object"
      and (.path | valid_path)
      and (.uid | type == "number" and . >= 0 and . <= 65535 and floor == .)
      and (.gid | type == "number" and . >= 0 and . <= 65535 and floor == .))
' "$config_file" >/dev/null; then
  echo "data_directories must contain relative paths and numeric uid/gid values in $config_file" >&2
  exit 1
fi
data_directories=()
while IFS= read -r data_directory; do
  data_directories+=("$data_directory")
done < <(jq -r '.data_directories // [] | .[] | [.path, (.uid | tostring), (.gid | tostring)] | @tsv' "$config_file")
if ! jq -e '
  (.secret_environment_variables // [])
  | type == "array" and all(.[]; type == "string" and test("^[A-Z_][A-Z0-9_]*$"))
' "$config_file" >/dev/null; then
  echo "secret_environment_variables must contain valid environment variable names in $config_file" >&2
  exit 1
fi
secret_environment_variables=()
while IFS= read -r secret_environment_variable; do
  secret_environment_variables+=("$secret_environment_variable")
done < <(jq -r '.secret_environment_variables // [] | .[]' "$config_file")
secret_values=()
remote_secret_reads=""
if (( ${#secret_environment_variables[@]} > 0 )) && ! command -v fnox >/dev/null 2>&1; then
  echo "fnox is required to load configured deployment secrets" >&2
  exit 1
fi
for secret_environment_variable in "${secret_environment_variables[@]}"; do
  if ! secret_value="$(fnox get --config "$repo_root/fnox.toml" "$secret_environment_variable")"; then
    echo "Could not load $secret_environment_variable from fnox" >&2
    exit 1
  fi
  if [[ -z "$secret_value" ]]; then
    echo "$secret_environment_variable is empty in fnox.toml" >&2
    exit 1
  fi
  secret_values+=("$secret_value")
  remote_secret_reads+="IFS= read -r $secret_environment_variable && export $secret_environment_variable && "
done
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
volume_seeds=()
while IFS= read -r volume_seed; do
  volume_seeds+=("$volume_seed")
done < <(jq -r '.volume_seeds // [] | .[] | [.source, .service, .target] | @tsv' "$config_file")
if (( ${#item_paths[@]} > 0 || ${#data_directories[@]} > 0 )); then
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

for data_directory in "${data_directories[@]}"; do
  IFS=$'\t' read -r data_path data_uid data_gid <<< "$data_directory"
  if [[ ! "$data_path" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ || "$data_path" == *..* ]]; then
    echo "Data directory path must be relative and contain only letters, numbers, dots, dashes, underscores, and slashes: $data_path" >&2
    exit 1
  fi
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

for data_directory in "${data_directories[@]}"; do
  IFS=$'\t' read -r data_path data_uid data_gid <<< "$data_directory"
  data_directory_path="$container_data/$data_path"
  echo "Preparing data directory: $data_path ($data_uid:$data_gid)"
  ssh "$ssh_target" "sudo mkdir -p '$data_directory_path' && sudo chown '$data_uid:$data_gid' '$data_directory_path'"
done

for volume_seed in "${volume_seeds[@]}"; do
  IFS=$'\t' read -r seed_source seed_service seed_target <<< "$volume_seed"
  echo "Copying volume seed: $seed_source"
  ssh "$ssh_target" "mkdir -p '$remote_container_dir/$seed_source'"
  scp -r "$compose_dir/$seed_source/." "$ssh_target:$remote_container_dir/$seed_source/"
done

for volume_seed in "${volume_seeds[@]}"; do
  IFS=$'\t' read -r seed_source seed_service seed_target <<< "$volume_seed"

  echo "Creating service container for volume seed: $seed_service"
  ssh "$ssh_target" "cd '$remote_container_dir' && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml pull '$seed_service' && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml create '$seed_service'"

  seed_container_id="$(ssh "$ssh_target" "cd '$remote_container_dir' && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml ps -aq '$seed_service' | head -n 1")"
  if [[ -z "$seed_container_id" ]]; then
    echo "Volume seed service container not found: $seed_service" >&2
    exit 1
  fi

  if ! ssh "$ssh_target" "docker inspect '$seed_container_id'" | jq -e --arg target "$seed_target" \
    '.[0].Mounts[] | select(.Destination == $target and .Type == "volume") | .Name' >/dev/null; then
    echo "Volume seed target is not a named volume mount for $seed_service: $seed_target" >&2
    exit 1
  fi

  echo "Seeding $seed_source into $seed_service:$seed_target"
  ssh "$ssh_target" "docker cp '$remote_container_dir/$seed_source/.' '$seed_container_id:$seed_target/'"
done

echo "Starting $container_name remotely..."
if (( ${#secret_environment_variables[@]} > 0 )); then
  for compose_action in "pull" "up -d"; do
    printf '%s\n' "${secret_values[@]}" | ssh "$ssh_target" \
      "cd '$remote_container_dir' && $remote_secret_reads PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml $compose_action"
  done
else
  ssh "$ssh_target" "cd '$remote_container_dir' && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml pull && PORT='$port' docker compose --env-file .env.remote -f docker-compose.yml up -d"
fi

printf '\033[0;32mDone!\033[0m\n'
