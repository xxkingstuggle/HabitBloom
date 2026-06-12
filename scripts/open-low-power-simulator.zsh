#!/usr/bin/env zsh
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

open -a Simulator

if ! pgrep -f "$repo_dir/scripts/watch-low-power-simulator.zsh" >/dev/null; then
  nohup "$repo_dir/scripts/watch-low-power-simulator.zsh" \
    > "$repo_dir/work/low-power-simulator-watch.out.log" \
    2> "$repo_dir/work/low-power-simulator-watch.err.log" &
  echo $! > "$repo_dir/work/low-power-simulator-watch.pid"
fi

sleep 2
"$repo_dir/scripts/low-power-simulator.zsh" >/dev/null 2>&1 || true
