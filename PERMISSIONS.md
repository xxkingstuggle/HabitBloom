# Permissions and Free Signing Check

This project is intended to work with local/free Apple signing for personal sideload testing.

## Current Entitlements

| Capability | Used By | Current Status | Free Apple Developer Risk |
| --- | --- | --- | --- |
| App Groups | App + Widgets | Enabled through `$(HABITBLOOM_APP_GROUP)` | Kept as a local/Xcode fallback. Real-device sideload builds use Cloudflare remote snapshots because third-party resigning can make App Group sharing unreliable. |
| CloudKit / iCloud containers | Not used | Removed | Do not enable unless a paid Apple Developer Program account is available. |
| Push Notifications | Not used | No `aps-environment` entitlement | Do not enable for the current self-signed build. |
| Local Notifications | App | Runtime permission only | OK. Uses `UserNotifications`; this is not the Push Notifications entitlement. |
| Time Sensitive Notifications | Not used | Not enabled | Avoid for now. |
| Live Activities / Dynamic Island | Not used | Not enabled | Avoid for now. It adds capability and review/signing complexity. |
| Photos | App | `NSPhotoLibraryUsageDescription` present | OK. User selects images through the system picker. |
| Cloudflare text backup | App | HTTPS requests only | OK. No Apple entitlement required. Does not use CloudKit containers. |

## Checked Project Files

- `HabitBloomApp/Support/HabitBloom.entitlements`
- `HabitBloomWidgets/HabitBloomWidgets.entitlements`
- `HabitBloomApp/Support/Info.plist`
- `HabitBloomWidgets/Info.plist`
- `project.yml`
- `Config/RemoteConfig.xcconfig`

## Maintenance Rule

Before adding a feature that sounds system-level, check whether it needs a new entitlement. Features to be careful with:

- iCloud / CloudKit sync
- Push notifications
- Live Activities / Dynamic Island
- Associated Domains
- Sign in with Apple
- HealthKit
- HomeKit
- Background modes beyond ordinary local notifications

## Apple References

- Supported iOS capabilities by membership: https://developer.apple.com/help/account/reference/supported-capabilities-ios/
- UserNotifications framework: https://developer.apple.com/documentation/usernotifications
- WidgetKit framework: https://developer.apple.com/documentation/widgetkit
- App Groups capability: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups
