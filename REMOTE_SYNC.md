# Remote Sync Setup

HabitBloom can run fully local. Remote widget refresh and cloud text backup are optional.

The public repository must not contain a real Worker URL, device key, or write token.

## Required Values

- `HABITBLOOM_REMOTE_BASE_URL`: Cloudflare Worker URL, for example `https://your-worker.your-account.workers.dev`
- `HABITBLOOM_REMOTE_DEVICE_KEY`: a long random per-user key shared by the app and widget
- `HABITBLOOM_REMOTE_WRITE_TOKEN`: a long random write token used only by the main app

The widget only reads `HABITBLOOM_REMOTE_BASE_URL` and `HABITBLOOM_REMOTE_DEVICE_KEY`.

## Xcode Build

Public defaults live in `Config/RemoteConfig.xcconfig`.

For local builds, copy the ignored override template:

```sh
cp Config/RemoteConfig.local.xcconfig.example Config/RemoteConfig.local.xcconfig
```

Then fill these values:

```text
HABITBLOOM_REMOTE_BASE_URL = https:/$()/your-worker.your-account.workers.dev
HABITBLOOM_REMOTE_DEVICE_KEY = your-long-random-device-key
HABITBLOOM_REMOTE_WRITE_TOKEN = your-long-random-write-token
```

Use `https:/$()/...` inside `.xcconfig` files so Xcode expands it to `https://...` without treating `//` as a comment.

The widget target does not need the write token, but leaving the setting available at project level is fine.

## Command Line Build

```sh
xcodebuild \
  -project HabitBloom.xcodeproj \
  -scheme HabitBloom \
  -configuration Release \
  -sdk iphoneos \
  HABITBLOOM_REMOTE_BASE_URL="https://your-worker.your-account.workers.dev" \
  HABITBLOOM_REMOTE_DEVICE_KEY="your-long-random-device-key" \
  HABITBLOOM_REMOTE_WRITE_TOKEN="your-long-random-write-token" \
  build
```

## Cloudflare Worker

Backend code lives in `cloudflare/habitbloom-widget`.

For local development, create an ignored file:

```sh
cp cloudflare/habitbloom-widget/.dev.vars.example cloudflare/habitbloom-widget/.dev.vars
```

Then fill:

```text
WRITE_TOKEN=your-long-random-write-token
```

For production, set the Worker secret in Cloudflare:

```sh
npx wrangler secret put WRITE_TOKEN
```

## Backup Boundary

Cloud backup stores only lightweight text data:

- habit ID
- name
- icon
- color and card style
- target frequency
- reminder settings
- sort order and creation date
- check-in dates, completion state, notes

It intentionally does not store custom images. If an old backup does not contain color or card style, restore can use the latest widget snapshot as a lightweight style fallback.
