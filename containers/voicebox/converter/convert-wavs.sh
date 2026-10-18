#!/bin/sh
set -eu

output_dir=/app/data/generations
poll_seconds=5
settle_seconds=2

while :; do
  for wav in "$output_dir"/*.wav; do
    [ -f "$wav" ] || continue

    mp3=${wav%.wav}.mp3
    if [ -f "$mp3" ] && [ ! "$wav" -nt "$mp3" ]; then
      continue
    fi

    size_before=$(stat -c '%s' "$wav" 2>/dev/null || echo 0)
    [ "$size_before" -gt 44 ] || continue
    sleep "$settle_seconds"
    size_after=$(stat -c '%s' "$wav" 2>/dev/null || echo 0)
    [ "$size_before" = "$size_after" ] || continue

    temp_mp3=${mp3%.mp3}.tmp.mp3
    if ffmpeg -nostdin -hide_banner -loglevel error -y \
      -i "$wav" -codec:a libmp3lame -q:a 2 "$temp_mp3"; then
      mv -f "$temp_mp3" "$mp3"
      echo "Created $mp3"
    else
      rm -f "$temp_mp3"
      echo "Could not convert $wav" >&2
    fi
  done

  sleep "$poll_seconds"
done
