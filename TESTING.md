# Testing HabitBloom

## Fast Local Checks

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
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
- Change widget-selected habit and confirm the displayed habit changes.
- Set reminders and confirm notification scheduling still works.
- Use Settings to upload a cloud backup and restore from the server.

## Long-Term Stability Checks

- Test with 50+ habits and several years of check-ins.
- Test with multiple image-card habits.
- Confirm widget refresh does not rewrite unchanged images every time.
- Confirm the app launches quickly after many check-ins.
- Confirm cloud backup stays small because it excludes custom image data.
