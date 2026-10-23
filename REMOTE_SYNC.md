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

## Widget Images over Remote Sync

Image-card snapshots no longer embed image bytes in every request. The app keeps a per-device image manifest on the Worker:

- `PUT /v1/image/<deviceKey>/<fileName>` uploads one optimized JPEG (only when its fingerprint changes). Auth required.
- `GET /v1/image/<deviceKey>/<fileName>` serves an immutable JPEG. No auth: file names embed a content fingerprint and the device key path is the capability.
- `GET/PUT /v1/images/<deviceKey>` reads/writes the manifest (`{"files": [...]}`). Auth required for `PUT`.

Snapshots and check-in payloads carry `imageFileName` references only. Widgets running where the App Group works read images from the local `WidgetImages` directory; sideloaded widgets fall back to the embedded `imageData` only when the remote snapshot still carries it.

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
