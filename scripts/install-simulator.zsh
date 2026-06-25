#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_NAME="${1:-iPhone 17 Pro}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
BUNDLE_ID="${HABITBLOOM_SIMULATOR_BUNDLE_ID:-com.example.HabitBloom}"

if [[ -f "$ROOT_DIR/Config/RemoteConfig.local.xcconfig" ]]; then
  local_id="$(sed -n 's/^HABITBLOOM_APP_BUNDLE_ID[[:space:]]*=[[:space:]]*//p' "$ROOT_DIR/Config/RemoteConfig.local.xcconfig" | tail -1)"
  if [[ -n "${local_id:-}" ]]; then
    BUNDLE_ID="$local_id"
  fi
fi

udid="$(xcrun simctl list devices available | sed -n "s/.*$DEVICE_NAME (\\([A-F0-9-]*\\)) (.*/\\1/p" | head -1)"
if [[ -z "$udid" ]]; then
  echo "Simulator not found: $DEVICE_NAME" >&2
  echo "Available devices:" >&2
  xcrun simctl list devices available >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT_DIR/HabitBloom.xcodeproj" \
  -scheme HabitBloom \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/HabitBloom.app"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
open -a Simulator
xcrun simctl install "$udid" "$app_path"
xcrun simctl launch "$udid" "$BUNDLE_ID"

echo "Installed and launched HabitBloom on $DEVICE_NAME"
