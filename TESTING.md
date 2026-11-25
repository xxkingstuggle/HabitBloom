# Testing HabitBloom

## Fast Local Checks

```sh
swift build
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
(cd cloudflare/habitbloom-widget && npm run typecheck && npm test)
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build
```

The smoke test covers `HabitCore` streak/month/reminder logic and `HabitWidgetShared` sync/codec/rollover/backup-dedup protocols. The stress test simulates hundreds of habits, years of check-ins, and large backup conflict plans. The Worker test suite (`node --test`) verifies auth, header sanitization, JPEG validation, manifest orphan cleanup, and incremental check-in concurrency.

## Manual App Checks

- Search icons by Chinese keywords, English SF Symbol names, and emoji characters.
- Select an emoji icon and a system icon, save, reopen the editor, and confirm the icon persists.
- Paste a custom emoji and enter a valid SF Symbol name.
- Enter an invalid SF Symbol name and confirm the picker shows it as unavailable instead of crashing.
- Verify the live WYSIWYG preview card, color swatches, and weekday presets in `HabitEditorView` update immediately.
- Create, edit, reorder, and delete habits (confirm `⌘N` and `⌘1`/`⌘2`/`⌘3` work on Mac Catalyst and Home/Stats switch to centered 2-column grids on wide windows).
- On an empty database, confirm one-tap quick templates create habits immediately.
- Switch card styles between soft, glass, minimal, and image.
- Import a large photo and confirm the app remains responsive while scrolling (decoded via `StickerImageCache`).
- Confirm image cards show correctly in the app and widgets.
- Toggle today's check-in repeatedly and confirm stats update.
- Toggle several habits quickly and confirm sound/animation feedback does not stack into visible lag.
- Change widget-selected habit and confirm the displayed habit changes.
- Set reminders and confirm notification scheduling still works; unchecking today restores the same-day reminder and deleting a habit removes orphan notifications.
- Toggle Dark Mode, Reduce Transparency, and Reduce Motion in system accessibility settings and verify card, chip, calendar, and widget readability.
- Use Settings to check the remote connection status capsule, export/import local JSON, and preview diffs/conflicts before applying keep-local or overwrite merges.

## Regression Checks for the 2026-10 Revival

- Streak: create a daily habit with check-ins up to yesterday; confirm the streak still shows before today's check-in, then +1 after.
- Stats calendar: tap a past day to backfill a check-in; tap again to cancel; confirm future dates are disabled; switch months and confirm the displayed completion rate tracks the selected month; long-press/right-click to add a note and confirm the dot marker.
- Stats icons: give a habit an emoji icon and confirm the Stats page renders it (not a blank SF Symbol).
- Today grouping: create a weekend-only habit and confirm it appears under "今日休息" on weekdays and is excluded from the "完成 X/Y" counter.
- Reminder suppression: set a reminder a few minutes ahead, check in, and confirm no notification fires for that habit today.
- Widget check-in: tap the circle on the single-habit widget and confirm the app shows the same state after launch (App Group path on Mac / Xcode install; remote path when sideloaded).
- Local/cloud backup: export JSON, edit a habit or day's check-in locally, re-import the JSON, and confirm the conflict preview sheet detects the conflict and respects both "保留本地优先" and "覆盖更新".
- Remote image dedup & cleanup: add two image cards, replace/remove one, and confirm `PUT /v1/images/<deviceKey>` cleans up orphaned image keys and `/v1/checkin` only sends incremental fields.

## Long-Term Stability Checks

- Test with 50+ habits and several years of check-ins.
- Test with multiple image-card habits.
- Confirm widget refresh does not rewrite unchanged images every time.
- Confirm the app launches quickly after many check-ins.
- Confirm normal app foreground/background refreshes do not trigger full cloud-backup uploads.
- Confirm a burst of check-ins coalesces into one delayed text backup while widget snapshots still refresh quickly.
- Confirm cloud backup stays small because it excludes custom image data.
