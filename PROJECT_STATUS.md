# HabitBloom Project Status

This document tracks the current implementation state for maintainers.

## Current Version Scope

HabitBloom is a SwiftUI habit tracker with local SwiftData storage, configurable habit cards, WidgetKit widgets, local reminders, and optional Cloudflare-based remote widget snapshots and text backup.

The current product direction is:

- keep the app fast and reliable for daily personal use
- keep signing requirements minimal
- keep remote sync lightweight and private
- avoid storing large image data in the remote backend
- keep the public repository free of secrets and generated packages

## Implemented

- iOS app built with SwiftUI and SwiftData
- Mac Catalyst desktop optimization: centered `1080pt` container with adaptive 2-column grids on Home & Stats, hover highlights, rich context menus, and keyboard shortcuts (`⌘N`, `⌘1`/`⌘2`/`⌘3`)
- Habit creation and editing: live WYSIWYG card preview, visual palette swatch selector, segmented card styles, weekday presets (`每天`/`工作日`/`周末`), icon picker, reminders, custom image cards, and monotonic `sortOrder`
- Icon picker with curated emoji and SF Symbols categories, search, and custom input
- Sticker-style habit cards on the home screen, grouped into "due today" and "resting today", plus a zero-habit empty state with one-tap quick templates
- Full `accessibilityReduceTransparency`, `accessibilityReduceMotion`, and dark-mode contrast adaptation across the app and all 3 widget families
- Check-in sound and card animation feedback (respects Reduce Motion)
- Bounded-cost `NSCache` sticker image decode cache indexed by content fingerprint and pixel size to avoid re-decoding during scroll
- Local notification scheduling per habit, with completed-today suppression, same-day restoration on uncheck, and orphan notification cleanup on habit deletion
- Statistics: current streak, historical best streak, total completed days, dynamic selected-month completion rate, and an interactive month calendar (future dates disabled; tap past/today to backfill or cancel; long-press/right-click for daily notes)
- Streak counting keeps the accumulated run visible while today is still unchecked
- Widget extension: single habit, multi habit (family-aware row capacity & overflow hint), and summary widgets with interactive check-in buttons (iOS 17+ / macOS 14+) and cross-midnight day rollover
- Deterministic startup/foreground sync sequencing: merges widget check-ins first, clears the local App Group queue only after `context.save()` succeeds, arbitrates local queue vs. remote snapshot by per-habit `updatedAt`, ignores stale previous-day snapshots, and then refreshes stats and snapshots
- App Group widget snapshot sharing as a local fallback
- Hardened Cloudflare Workers + Durable Objects snapshot sync: constant-time `Authorization: Bearer` validation, external `x-habitbloom-*` header stripping, input & payload size limits, JPEG magic-byte validation, private cache headers + `nosniff`, and incremental `/v1/checkin` updates with cross-midnight rollover
- Cloudflare text backup and local JSON export/import sharing the same schema and dual-format ISO-8601 (fractional + whole-second) codec
- Same-day `(habitID, normalizedDay)` check-in deduplication and a Settings backup conflict preview sheet displaying diff metrics, per-day conflicts, and keep-local vs. overwrite merge strategies
- Remote connection status capsule in Settings (Writable / Read-Only / Local Offline)
- Remote image dedup: widget image cards upload only when their fingerprint changes; `PUT /v1/images/<deviceKey>` normalizes both `{"files": [...]}` and array manifests and purges orphaned `image/*` objects in Durable Object storage
- Local image optimization before storing custom sticker images
- Derived habit stats cached per refresh pass to avoid repeated full-history scans during rendering
- Debounced cloud backup so ordinary foreground/background refreshes do not upload full history
- Cross-midnight refresh: the app listens for day-change notifications and widget timelines carry a next-midnight entry
- Core smoke/stress test executables (including `HabitWidgetShared` protocol coverage) and Worker `node --test` unit suite
- Free-signing capability audit in `PERMISSIONS.md`

## Not Implemented

- iCloud / CloudKit sync
- Push-notification based server reminders
- Time Sensitive Notifications
- Live Activities / Dynamic Island reminders
- Full manual image crop UI
- GitHub Releases workflow for packaged IPA delivery

## Signing Model

Current entitlements are intentionally minimal.

- App Groups are enabled as a local fallback.
- Real-device sideload builds should prefer the Cloudflare snapshot path for widgets.
- CloudKit, Push Notifications, Time Sensitive Notifications, and Live Activities are not enabled.
- Local notifications are supported through runtime permission and do not require Push Notifications.

Check `PERMISSIONS.md` before adding any new Apple capability.

## Remote Data Boundary

Cloud backup stores lightweight app state:

- habit IDs, names, icons, colors, styles, schedules, reminders, sort order, and creation dates
- check-in dates, completion state, and notes

Cloud backup does not store custom images. Image cards remain local assets.

## Maintenance Rules

- Do not commit Worker URLs, device keys, write tokens, certificates, provisioning profiles, IPA files, archives, build folders, or local Xcode state.
- Keep remote sync values in private Xcode build settings, ignored local config files, or command-line build settings.
- Keep Bundle IDs stable unless there is a deliberate migration plan.
- Prefer unsigned builds for CI-style checks when signing is not required.

Recommended checks before larger changes:

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' build
```
