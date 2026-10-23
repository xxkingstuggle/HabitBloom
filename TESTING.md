# Testing HabitBloom

## Fast Local Checks

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -allowProvisioningUpdates build
```

The smoke test catches basic logic regressions. The stress test simulates hundreds of habits and years of check-ins, so it is useful before larger refactors.

## Manual App Checks

- Search icons by Chinese keywords, English SF Symbol names, and emoji characters.
- Select an emoji icon and a system icon, save, reopen the editor, and confirm the icon persists.
- Paste a custom emoji and enter a valid SF Symbol name.
- Enter an invalid SF Symbol name and confirm the picker shows it as unavailable instead of crashing.
- Create, edit, reorder, and delete habits.
- Switch card styles between soft, glass, minimal, and image.
- Import a large photo and confirm the app remains responsive.
- Confirm image cards show correctly in the app and widgets.
- Toggle today's check-in repeatedly and confirm stats update.
- Toggle several habits quickly and confirm sound/animation feedback does not stack into visible lag.
- Change widget-selected habit and confirm the displayed habit changes.
- Set reminders and confirm notification scheduling still works.
- Use Settings to upload a cloud backup and restore from the server.

## Regression Checks for the 2026-10 Revival

- Streak: create a daily habit with check-ins up to yesterday; confirm the streak still shows before today's check-in, then +1 after.
- Stats calendar: tap a past day to backfill a check-in; tap again to cancel; long-press to add a note and confirm the dot marker.
- Stats icons: give a habit an emoji icon and confirm the Stats page renders it (not a blank SF Symbol).
- Today grouping: create a weekend-only habit and confirm it appears under "今日休息" on weekdays and is excluded from the "完成 X/Y" counter.
- Reminder suppression: set a reminder a few minutes ahead, check in, and confirm no notification fires for that habit today.
- Widget check-in: tap the circle on the single-habit widget and confirm the app shows the same state after launch (App Group path on Mac / Xcode install; remote path when sideloaded).
- Local backup: export JSON, delete a habit, import the JSON, and confirm the habit and its check-ins return.
- Remote image dedup: add two image cards, check in on a text habit, and confirm the `/v1/checkin` body no longer embeds image data (only file names).

## Long-Term Stability Checks

- Test with 50+ habits and several years of check-ins.
- Test with multiple image-card habits.
- Confirm widget refresh does not rewrite unchanged images every time.
- Confirm the app launches quickly after many check-ins.
- Confirm normal app foreground/background refreshes do not trigger full cloud-backup uploads.
- Confirm a burst of check-ins coalesces into one delayed text backup while widget snapshots still refresh quickly.
- Confirm cloud backup stays small because it excludes custom image data.
