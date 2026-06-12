#!/usr/bin/env zsh
set -euo pipefail

patterns=(
  "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
  "com.apple.CoreSimulator.CoreSimulatorService"
  "simdiskimaged"
  "SimulatorTrampoline"
  "SimLaunchHost"
  "SimRenderServer"
  "SimMetalHost"
  "SimStreamProcessorService"
  "SimAudioProcessorService"
  "/Library/Developer/CoreSimulator/Volumes/.*/RuntimeRoot/"
  "/usr/libexec/CoreSimulatorBridge"
)

seen_pids=()

for pattern in "${patterns[@]}"; do
  pgrep -f "$pattern" | while read -r pid; do
    [[ -n "$pid" ]] || continue
    if [[ " ${seen_pids[*]} " == *" $pid "* ]]; then
      continue
    fi
    seen_pids+=("$pid")
    taskpolicy -b -p "$pid" 2>/dev/null || true
    renice 15 -p "$pid" >/dev/null 2>&1 || true
    echo "low-power simulator pid=$pid pattern=$pattern"
  done
done
