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
- Mac Catalyst build for desktop use and local testing
- Habit creation and editing: name, icon, color, card style, target weekdays, reminders, image cards, and ordering
- Icon picker with curated emoji and SF Symbols categories, search, and custom input
- Sticker-style habit cards on the home screen, grouped into "due today" and "resting today"
- Check-in sound and card animation feedback
- Local notification scheduling per habit, with completed-today suppression so finished habits do not nag
- Statistics: current streak, total completed days, monthly completion rate, and an interactive month calendar (tap to backfill/cancel a day, long-press for daily notes)
- Streak counting keeps the accumulated run visible while today is still unchecked
- Widget extension: single habit, multi habit, and summary widgets with interactive check-in buttons (iOS 17+ / macOS 14+)
- Widget check-ins merge back into SwiftData on next app launch via the App Group queue, and via the remote snapshot when sideloading breaks the App Group
- App Group widget snapshot sharing as a local fallback
- Cloudflare Workers + Durable Objects snapshot sync for sideloaded widget reliability
- Cloudflare text backup for habits, lightweight styling, schedules, and check-in records
- Remote image dedup: widget image cards upload only when their fingerprint changes; snapshots reference images by file name
- Local JSON export/import backup in Settings, same schema as the cloud archive
- Local image optimization before storing custom sticker images
- Derived habit stats cached per refresh pass to avoid repeated full-history scans during rendering
- Debounced cloud backup so ordinary foreground/background refreshes do not upload full history
- Cross-midnight refresh: the app listens for day-change notifications and widget timelines carry a next-midnight entry
- Core smoke and stress test executables (streak regression locked in)
- Free-signing capability audit in `PERMISSIONS.md`

## Not Implemented

- iCloud / CloudKit sync
- Push-notification based server reminders
- Time Sensitive Notifications
- Live Activities / Dynamic Island reminders
- Full manual image crop UI
- Full remote backup conflict-resolution UI
- Full image decode cache for app card rendering
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
