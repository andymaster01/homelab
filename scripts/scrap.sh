#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
containers_dir="$repo_root/containers"
output_file="$containers_dir/homepage/static-data/household-items.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to generate Homepage container data" >&2
  exit 1
fi

records_file="$(mktemp)"
output_file_tmp="$(mktemp "$output_file.XXXXXX")"
trap 'rm -f "$records_file" "$output_file_tmp"' EXIT

while IFS= read -r -d '' config_file; do
  compose_file="$(dirname -- "$config_file")/docker-compose.yml"
  if [[ ! -f "$compose_file" ]]; then
    echo "Compose file not found: $compose_file" >&2
    exit 1
  fi

  remote="$(jq -er '.remote | strings | select(length > 0)' "$config_file")"
  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    printf '%s\t%s\n' "$remote" "$container_name" >> "$records_file"
  done < <(sed -nE 's/^[[:space:]]*container_name:[[:space:]]*//p' "$compose_file" | tr -d "\"'")
done < <(find "$containers_dir" -type f -name config.json -print0)

jq -Rn '
  [inputs | split("\t") | {remote: .[0], container: .[1]}]
  | sort_by(.remote)
  | group_by(.remote)
  | map({
      remote: .[0].remote,
      containers: (map(.container) | unique | sort),
      container_names: (map(.container) | unique | sort | join(", "))
    })
  | {items: .}
' "$records_file" > "$output_file_tmp"

mv "$output_file_tmp" "$output_file"
echo "Generated $output_file"
