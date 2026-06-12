#!/usr/bin/env zsh
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
low_power_script="$repo_dir/scripts/low-power-simulator.zsh"
log_file="$repo_dir/work/low-power-simulator-watch.log"
idle_count=0

mkdir -p "$repo_dir/work"
echo "watcher started $(date)" >> "$log_file"

while true; do
  if pgrep -f "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" >/dev/null; then
    idle_count=0
    "$low_power_script" >> "$log_file" 2>&1 || true
  else
    idle_count=$((idle_count + 1))
    if (( idle_count >= 3 )); then
      echo "watcher stopped $(date)" >> "$log_file"
      exit 0
    fi
  fi
  sleep 8
done
