# HabitBloom Project Status

## Implemented

- iOS SwiftUI app with SwiftData local storage.
- Designed-for-iPhone-on-Mac support through the iOS target.
- Habit creation and editing: name, icon, color, card style, target weekdays, reminders, and image cards.
- Icon picker with curated emoji and SF Symbols categories, search, and custom input.
- Sticker-style habit cards on the home screen.
- Local notification scheduling per habit.
- Statistics: current streak, total completed days, monthly completion rate, and month heatmap.
- Widget extension: single habit, multi habit, and summary widgets.
- Remote widget snapshots through Cloudflare Workers + Durable Objects for sideloaded builds; App Group snapshot sharing remains as a local fallback.
- Cloudflare text backup for habits and check-in records; images and card styling are intentionally excluded from long-term backup.
- Check-in sound and card animation feedback.
- Local image optimization before storing custom sticker images.
- Derived habit stats are cached per refresh pass so the home screen and widget snapshot writer do not repeatedly scan the same check-in history.
- Automatic cloud backup is debounced separately from widget snapshot refreshes; ordinary foreground/background refreshes no longer upload full history.
- Mac Catalyst builds are enabled for quick desktop testing of the main app.
- Core smoke and stress test executables.
- Free-signing capability audit documented in `PERMISSIONS.md`.

## Not Implemented Yet

- iCloud/CloudKit sync. This is intentionally removed because the current signing/account setup cannot use iCloud capabilities.
- True interactive widget check-in button. Current widgets are display/configuration focused.
- Dynamic Island / Live Activities reminders. This should stay blocked unless the signing/account capability path is clear.
- Full image crop UI. Current import does automatic center crop to the sticker ratio and compression.
- GitHub Releases for IPA delivery. Source control comes first; IPA publishing can come later.
- Full remote backup conflict resolution. Current cloud restore is an overwrite/update merge by stable IDs.
- Full image decode cache for app cards. Images are compressed at import, but image-card rendering can still be profiled later if a large image library is used.

## v0.1.0 Usable Release Criteria

- Source is maintained in Git on `main`.
- Xcode project builds for iOS Simulator.
- Core smoke and stress tests pass.
- The app remains free-signing friendly: no CloudKit, Push Notifications, Time Sensitive Notifications, or Live Activities entitlements.
- IPA packaging is manual; installable test IPAs can be produced when needed.

## Free Signing Status

- Current entitlements are intentionally minimal.
- App Groups remain enabled as a local fallback. Real-device sideload builds should use the Cloudflare snapshot path because App Group behavior can break after third-party resigning.
- CloudKit, Push Notifications, Time Sensitive Notifications, and Live Activities are not enabled.
- See `PERMISSIONS.md` before adding any new Apple capability.

## Maintenance Rules

- The repository can be public if real Worker URLs, device keys, write tokens, certificates, profiles, and IPA files are not committed.
- Configure private remote sync values through local Xcode build settings or command-line build variables. See `REMOTE_SYNC.md`.
- Do not commit build outputs, IPA files, signing certificates, provisioning profiles, or local Xcode state.
- Before important changes, run:

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -allowProvisioningUpdates build
```

- For UI or widget changes, also build the Xcode scheme and test on the current simulator/device.
