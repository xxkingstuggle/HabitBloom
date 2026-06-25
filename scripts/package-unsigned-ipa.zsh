#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/ipa}"
CONFIGURATION="${CONFIGURATION:-Release}"

xcodebuild \
  -project "$ROOT_DIR/HabitBloom.xcodeproj" \
  -scheme HabitBloom \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

app_path="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/HabitBloom.app"
payload_dir="$OUTPUT_DIR/Payload"
ipa_path="$OUTPUT_DIR/HabitBloom-unsigned.ipa"

rm -rf "$payload_dir"
mkdir -p "$payload_dir"
ditto "$app_path" "$payload_dir/HabitBloom.app"

rm -f "$ipa_path"
(cd "$OUTPUT_DIR" && /usr/bin/zip -qry "$ipa_path" Payload)

echo "$ipa_path"
