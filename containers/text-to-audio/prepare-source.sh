#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checkout_dir="$script_dir/.upstream"
build_context_dir="$script_dir/build-context"
source_url="https://github.com/jamiepine/voicebox.git"
source_revision="8af7efe62fab8d33e2a5dfbedabaa45f68a5184f"

if [[ -e "$checkout_dir" || -e "$build_context_dir" ]]; then
  echo "Voicebox source preparation already exists under $script_dir" >&2
  echo "Remove .upstream and build-context before preparing a fresh checkout." >&2
  exit 1
fi

git clone --filter=blob:none --no-checkout "$source_url" "$checkout_dir"
git -C "$checkout_dir" fetch --depth=1 origin "$source_revision"
git -C "$checkout_dir" checkout --detach FETCH_HEAD

actual_revision="$(git -C "$checkout_dir" rev-parse HEAD)"
if [[ "$actual_revision" != "$source_revision" ]]; then
  echo "Unexpected Voicebox revision: $actual_revision" >&2
  exit 1
fi

mkdir -p "$build_context_dir"
git -C "$checkout_dir" archive "$source_revision" | tar -x -C "$build_context_dir"

mkdir -p "$build_context_dir/defuddle-api"
cp -R "$script_dir/defuddle-api/." "$build_context_dir/defuddle-api/"

echo "Prepared Voicebox source at $actual_revision"
