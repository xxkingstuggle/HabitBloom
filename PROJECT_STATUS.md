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
- App Group snapshot sharing for widget data and widget image files.
- Manual folder export/import for sync-style backup.
- Check-in sound and card animation feedback.
- Local image optimization before storing custom sticker images.
- Core smoke and stress test executables.
- Free-signing capability audit documented in `PERMISSIONS.md`.

## Not Implemented Yet

- iCloud/CloudKit sync. This is intentionally removed because the current signing/account setup cannot use iCloud capabilities.
- True interactive widget check-in button. Current widgets are display/configuration focused.
- Dynamic Island / Live Activities reminders. This should stay blocked unless the signing/account capability path is clear.
- Full image crop UI. Current import does automatic center crop to the sticker ratio and compression.
- GitHub Releases for IPA delivery. Source control comes first; IPA publishing can come later.

## v0.1.0 Usable Release Criteria

- Source is maintained in Git on `main`.
- Xcode project builds for iOS Simulator.
- Core smoke and stress tests pass.
- The app remains free-signing friendly: no CloudKit, Push Notifications, Time Sensitive Notifications, or Live Activities entitlements.
- IPA packaging is intentionally deferred.

## Free Signing Status

- Current entitlements are intentionally minimal.
- App Groups are enabled because widgets need shared data.
- CloudKit, Push Notifications, Time Sensitive Notifications, and Live Activities are not enabled.
- See `PERMISSIONS.md` before adding any new Apple capability.

## Maintenance Rules

- Keep the repository private while personal Bundle IDs, Team ID, and App Group IDs are inside the project.
- Do not commit build outputs, IPA files, signing certificates, provisioning profiles, or local Xcode state.
- Before important changes, run:

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
```

- For UI or widget changes, also build the Xcode scheme and test on the current simulator/device.
